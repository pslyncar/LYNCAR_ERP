from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.core.security import hash_password, verify_password
from app.models.pdv_operator import PdvOperator
from app.models.user import User
from app.schemas.pdv_operator import (
    PdvAuthorizationRequest,
    PdvAuthorizationResponse,
    PdvOperatorCreate,
    PdvOperatorRead,
    PdvOperatorUpdate,
)

router = APIRouter()


def normalize_code(code: str) -> str:
    return code.strip().upper()


def get_operator_or_404(db: Session, operator_id: int) -> PdvOperator:
    operator = db.get(PdvOperator, operator_id)
    if operator is None:
        raise HTTPException(status_code=404, detail="Operador de PDV não encontrado.")
    return operator


@router.get("/operators", response_model=list[PdvOperatorRead])
def list_pdv_operators(
    active_only: bool = True,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("pdv_operators:manage", "sales:create")
    ),
) -> list[PdvOperator]:
    query = select(PdvOperator).order_by(PdvOperator.name)
    if active_only:
        query = query.where(PdvOperator.active.is_(True))
    return list(db.scalars(query).all())


@router.post(
    "/operators",
    response_model=PdvOperatorRead,
    status_code=status.HTTP_201_CREATED,
)
def create_pdv_operator(
    operator_in: PdvOperatorCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("pdv_operators:manage")),
) -> PdvOperator:
    code = normalize_code(operator_in.code)
    if db.scalar(select(PdvOperator).where(PdvOperator.code == code)) is not None:
        raise HTTPException(status_code=409, detail="Código de operador já cadastrado.")
    operator = PdvOperator(
        name=operator_in.name,
        code=code,
        pin_hash=hash_password(operator_in.pin),
        role=operator_in.role,
        can_open_cash=operator_in.can_open_cash,
        can_authorize_withdrawal=operator_in.can_authorize_withdrawal,
        can_authorize_cancel=operator_in.can_authorize_cancel,
        can_authorize_discount=operator_in.can_authorize_discount,
        active=operator_in.active,
        notes=operator_in.notes,
    )
    db.add(operator)
    db.commit()
    db.refresh(operator)
    return operator


@router.put("/operators/{operator_id}", response_model=PdvOperatorRead)
def update_pdv_operator(
    operator_id: int,
    operator_in: PdvOperatorUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("pdv_operators:manage")),
) -> PdvOperator:
    operator = get_operator_or_404(db, operator_id)
    update_data = operator_in.model_dump(exclude_unset=True)
    if "code" in update_data:
        code = normalize_code(update_data.pop("code"))
        existing = db.scalar(
            select(PdvOperator).where(PdvOperator.code == code, PdvOperator.id != operator_id)
        )
        if existing is not None:
            raise HTTPException(status_code=409, detail="Código de operador já cadastrado.")
        operator.code = code
    if "pin" in update_data:
        operator.pin_hash = hash_password(update_data.pop("pin"))
    for field, value in update_data.items():
        setattr(operator, field, value)
    db.commit()
    db.refresh(operator)
    return operator


@router.delete("/operators/{operator_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_pdv_operator(
    operator_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("pdv_operators:manage")),
) -> None:
    operator = get_operator_or_404(db, operator_id)
    db.delete(operator)
    db.commit()


@router.post("/authorize", response_model=PdvAuthorizationResponse)
def authorize_pdv_action(
    authorization_in: PdvAuthorizationRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> PdvAuthorizationResponse:
    operator = db.scalar(
        select(PdvOperator).where(PdvOperator.code == normalize_code(authorization_in.code))
    )
    if (
        operator is None
        or not operator.active
        or not verify_password(authorization_in.pin, operator.pin_hash)
    ):
        raise HTTPException(status_code=401, detail="Código ou senha do operador inválido.")

    action_permissions = {
        "authorize_open_cash": operator.role == "fiscal",
        "authorize_close_cash": operator.role == "fiscal",
        "open_cash": operator.can_open_cash,
        "withdrawal": operator.can_authorize_withdrawal,
        "cancel_sale": operator.can_authorize_cancel,
        "discount": operator.can_authorize_discount,
    }
    if not action_permissions[authorization_in.action]:
        raise HTTPException(status_code=403, detail="Operador sem autorização para esta ação.")

    return PdvAuthorizationResponse(
        authorized=True,
        operator_id=operator.id,
        operator_name=operator.name,
        role=operator.role,
        message="Autorização aprovada.",
    )

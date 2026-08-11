from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.payable import Payable, PayablePayment
from app.models.stock_entry import StockEntry
from app.models.supplier import Supplier
from app.models.user import User
from app.schemas.payable import (
    PayableCreate,
    PayablePaymentCreate,
    PayableRead,
    PayableUpdate,
)

router = APIRouter()


def payable_number(payable_id: int) -> str:
    return f"CP{payable_id}"


def _money(value: Decimal) -> Decimal:
    return Decimal(value).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def get_payable_or_404(db: Session, payable_id: int) -> Payable:
    payable = db.scalar(
        select(Payable)
        .options(
            selectinload(Payable.payments),
            selectinload(Payable.supplier),
            selectinload(Payable.stock_entry),
        )
        .where(Payable.id == payable_id)
    )
    if payable is None:
        raise HTTPException(status_code=404, detail="Conta a pagar nao encontrada.")
    return payable


def validate_links(
    db: Session,
    supplier_id: int | None,
    stock_entry_id: int | None,
) -> None:
    if supplier_id is not None and db.get(Supplier, supplier_id) is None:
        raise HTTPException(status_code=404, detail="Fornecedor nao encontrado.")
    if stock_entry_id is not None and db.get(StockEntry, stock_entry_id) is None:
        raise HTTPException(status_code=404, detail="Entrada de mercadoria nao encontrada.")


@router.get("", response_model=list[PayableRead])
def list_payables(
    status_filter: str | None = Query(default=None, alias="status"),
    supplier_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("finance:view", "finance:payables:view")
    ),
) -> list[Payable]:
    query = (
        select(Payable)
        .options(
            selectinload(Payable.payments),
            selectinload(Payable.supplier),
            selectinload(Payable.stock_entry),
        )
        .order_by(Payable.due_date.asc().nulls_last(), Payable.created_at.desc())
        .limit(limit)
    )
    if status_filter:
        query = query.where(Payable.status == status_filter)
    if supplier_id is not None:
        query = query.where(Payable.supplier_id == supplier_id)
    return list(db.scalars(query).all())


@router.post("", response_model=PayableRead, status_code=status.HTTP_201_CREATED)
def create_payable(
    payable_in: PayableCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:payables:manage")),
) -> Payable:
    validate_links(db, payable_in.supplier_id, payable_in.stock_entry_id)
    payable = Payable(
        supplier_id=payable_in.supplier_id,
        stock_entry_id=payable_in.stock_entry_id,
        description=payable_in.description,
        document_number=payable_in.document_number,
        category=payable_in.category,
        original_amount=payable_in.original_amount,
        paid_amount=0,
        balance_amount=payable_in.original_amount,
        status="open",
        due_date=payable_in.due_date,
        issue_date=payable_in.issue_date,
        competence_date=payable_in.competence_date,
        notes=payable_in.notes,
    )
    db.add(payable)
    db.flush()
    payable.number = payable_number(payable.id)
    db.commit()
    return get_payable_or_404(db, payable.id)


@router.put("/{payable_id}", response_model=PayableRead)
def update_payable(
    payable_id: int,
    payable_in: PayableUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:payables:manage")),
) -> Payable:
    payable = get_payable_or_404(db, payable_id)
    if payable.status == "paid":
        raise HTTPException(status_code=400, detail="Conta paga nao pode ser editada.")
    data = payable_in.model_dump(exclude_unset=True)
    validate_links(db, data.get("supplier_id"), data.get("stock_entry_id"))
    for field, value in data.items():
        setattr(payable, field, value)
    db.commit()
    return get_payable_or_404(db, payable.id)


@router.delete("/{payable_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_payable(
    payable_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:payables:manage")),
) -> None:
    payable = get_payable_or_404(db, payable_id)
    if payable.payments or payable.paid_amount > 0:
        raise HTTPException(
            status_code=400,
            detail="Conta com pagamento registrado não pode ser excluída.",
        )
    db.delete(payable)
    db.commit()


@router.post("/{payable_id}/payments", response_model=PayableRead, status_code=status.HTTP_201_CREATED)
def pay_payable(
    payable_id: int,
    payment_in: PayablePaymentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:payables:manage")),
) -> Payable:
    payable = get_payable_or_404(db, payable_id)
    if payable.status == "paid" or payable.balance_amount <= 0:
        raise HTTPException(status_code=400, detail="Conta a pagar ja quitada.")
    payment_amount = _money(payment_in.amount)
    balance_amount = _money(payable.balance_amount)
    if payment_amount > balance_amount:
        raise HTTPException(status_code=400, detail="Pagamento maior que o saldo em aberto.")

    payable.payments.append(
        PayablePayment(
            user_id=current_user.id,
            amount=payment_amount,
            method=payment_in.method,
            notes=payment_in.notes,
        )
    )
    payable.paid_amount = _money(payable.paid_amount + payment_amount)
    payable.balance_amount = _money(payable.balance_amount - payment_amount)
    if _money(payable.balance_amount) <= 0:
        payable.balance_amount = 0
        payable.status = "paid"
        payable.settled_at = datetime.utcnow()
    else:
        payable.status = "partial"
    db.commit()
    return get_payable_or_404(db, payable.id)

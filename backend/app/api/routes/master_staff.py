from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.core.security import hash_password
from app.models.master_permission import MasterUserPermission
from app.models.master_user import MasterUser
from app.schemas.master_staff import (
    MasterPermissionRead,
    MasterStaffCreate,
    MasterStaffRead,
    MasterStaffUpdate,
)
from app.services.master_permissions import (
    MASTER_PERMISSION_DEFINITIONS,
    get_master_user_permission_codes,
    is_owner_master_user,
    master_permission_codes,
)

router = APIRouter()


def _read_staff(db, user: MasterUser) -> MasterStaffRead:
    return MasterStaffRead(
        id=user.id,
        name=user.name,
        email=user.email,
        active=user.active,
        must_change_password=user.must_change_password,
        permissions=get_master_user_permission_codes(db, user),
        created_at=user.created_at,
    )


def _validate_permissions(permissions: list[str]) -> list[str]:
    allowed = master_permission_codes()
    requested = sorted(set(permissions))
    invalid = [code for code in requested if code not in allowed]
    if invalid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Permissão master inválida: {', '.join(invalid)}.",
        )
    return requested


def _set_permissions(db, user: MasterUser, permissions: list[str]) -> None:
    if is_owner_master_user(user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="O usuário dono do master já possui acesso total.",
        )
    requested = _validate_permissions(permissions)
    db.execute(delete(MasterUserPermission).where(MasterUserPermission.user_id == user.id))
    for code in requested:
        db.add(MasterUserPermission(user_id=user.id, permission_code=code))


@router.get("/permissions", response_model=list[MasterPermissionRead])
def list_master_permissions(
    _: dict = Depends(require_master_permission("master:staff")),
) -> list[MasterPermissionRead]:
    return [MasterPermissionRead(**item) for item in MASTER_PERMISSION_DEFINITIONS]


@router.get("/staff", response_model=list[MasterStaffRead])
def list_master_staff(
    _: dict = Depends(require_master_permission("master:staff")),
) -> list[MasterStaffRead]:
    with MasterSessionLocal() as db:
        users = db.scalars(select(MasterUser).order_by(MasterUser.name)).all()
        return [_read_staff(db, user) for user in users]


@router.post("/staff", response_model=MasterStaffRead, status_code=status.HTTP_201_CREATED)
def create_master_staff(
    payload: MasterStaffCreate,
    _: dict = Depends(require_master_permission("master:staff")),
) -> MasterStaffRead:
    with MasterSessionLocal() as db:
        email = payload.email.lower()
        if db.scalar(select(MasterUser).where(MasterUser.email == email)) is not None:
            raise HTTPException(status_code=409, detail="E-mail já cadastrado no master.")
        user = MasterUser(
            name=payload.name.strip(),
            email=email,
            password_hash=hash_password(payload.password),
            must_change_password=payload.must_change_password,
            active=payload.active,
        )
        db.add(user)
        db.flush()
        _set_permissions(db, user, payload.permissions)
        db.commit()
        db.refresh(user)
        return _read_staff(db, user)


@router.put("/staff/{user_id}", response_model=MasterStaffRead)
def update_master_staff(
    user_id: int,
    payload: MasterStaffUpdate,
    _: dict = Depends(require_master_permission("master:staff")),
) -> MasterStaffRead:
    with MasterSessionLocal() as db:
        user = db.get(MasterUser, user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="Funcionário master não encontrado.")
        data = payload.model_dump(exclude_unset=True)
        if "email" in data and data["email"] is not None:
            email = str(data["email"]).lower()
            existing = db.scalar(
                select(MasterUser).where(MasterUser.email == email, MasterUser.id != user.id)
            )
            if existing is not None:
                raise HTTPException(status_code=409, detail="E-mail já cadastrado no master.")
            user.email = email
        if "name" in data and data["name"] is not None:
            user.name = str(data["name"]).strip()
        if "password" in data and data["password"]:
            user.password_hash = hash_password(str(data["password"]))
        if "active" in data and data["active"] is not None:
            user.active = bool(data["active"])
        if "must_change_password" in data and data["must_change_password"] is not None:
            user.must_change_password = bool(data["must_change_password"])
        if payload.permissions is not None:
            _set_permissions(db, user, payload.permissions)
        db.commit()
        db.refresh(user)
        return _read_staff(db, user)

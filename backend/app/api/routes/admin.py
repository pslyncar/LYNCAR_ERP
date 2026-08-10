from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
import re

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, require_any_permission, require_permission
from app.core.database import get_db
from app.core.security import decode_access_token, hash_password
from app.models.access_control import Permission, Role, UserPermission
from app.models.access_control import RolePermission
from app.models.user import User
from app.schemas.user import (
    PermissionRead,
    RoleCreate,
    RoleRead,
    RoleUpdate,
    UserCreate,
    UserPermissionSet,
    UserRead,
    UserUpdate,
)
from app.services.access_control import get_user_permission_codes
from app.services.company_modules import permission_allowed_by_modules
from app.services.master_user_index import (
    company_name_for_code,
    remove_user_index,
    require_duplicate_authorization,
    upsert_user_index,
)
from app.services.plan_limits import enforce_user_limit
from app.services.tenancy import get_enabled_modules_for_company

router = APIRouter()

_SYSTEM_ROLES = {"admin"}
_LEGACY_ROLES = {"technician", "seller", "cashier", "client"}
_SYSTEM_USER_EMAILS = {"_pdv_terminal@lyncar.local"}


def _enabled_modules_from_credentials(
    credentials: HTTPAuthorizationCredentials | None,
) -> list[str]:
    company_code = _company_code_from_credentials(credentials)
    return get_enabled_modules_for_company(company_code)


def _allowed_permission_codes(
    db: Session,
    enabled_modules: list[str],
) -> set[str]:
    permissions = db.scalars(select(Permission)).all()
    return {
        permission.code
        for permission in permissions
        if permission_allowed_by_modules(permission.code, enabled_modules)
    }


def _ensure_permission_allowed(
    permission_code: str,
    enabled_modules: list[str],
) -> None:
    if not permission_allowed_by_modules(permission_code, enabled_modules):
        raise HTTPException(
            status_code=403,
            detail="Permissao pertence a um modulo nao contratado para esta empresa.",
        )


def serialize_user(
    db: Session,
    user: User,
    enabled_modules: list[str] | None = None,
) -> UserRead:
    return UserRead(
        id=user.id,
        name=user.name,
        email=user.email,
        seller_code=user.seller_code,
        role=user.role,
        active=user.active,
        created_at=user.created_at,
        permissions=sorted(get_user_permission_codes(db, user, enabled_modules)),
    )


def _set_user_app_access(db: Session, user: User, allowed: bool | None) -> None:
    if allowed is None:
        return
    permission = db.scalar(select(Permission).where(Permission.code == "app:access"))
    if permission is None:
        return
    user_permission = db.scalar(
        select(UserPermission).where(
            UserPermission.user_id == user.id,
            UserPermission.permission_id == permission.id,
        )
    )
    if user_permission is None:
        db.add(
            UserPermission(
                user_id=user.id,
                permission_id=permission.id,
                allowed=allowed,
            )
        )
    else:
        user_permission.allowed = allowed


def _role_permission_codes(db: Session, role: Role, enabled_modules: list[str]) -> list[str]:
    codes = db.scalars(
        select(Permission.code)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(
            RolePermission.role_id == role.id,
            Permission.active.is_(True),
        )
        .order_by(Permission.module, Permission.label)
    ).all()
    return [
        code
        for code in codes
        if permission_allowed_by_modules(code, enabled_modules)
    ]


def serialize_role(db: Session, role: Role, enabled_modules: list[str]) -> RoleRead:
    return RoleRead(
        id=role.id,
        name=role.name,
        label=role.label,
        description=role.description,
        active=role.active,
        permissions=_role_permission_codes(db, role, enabled_modules),
    )


def _profile_slug(label: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")
    return slug or "perfil"


def _unique_role_name(db: Session, label: str, role_id: int | None = None) -> str:
    base = f"custom_{_profile_slug(label)}"[:24].rstrip("_")
    name = base
    index = 2
    while True:
        query = select(Role).where(Role.name == name)
        if role_id is not None:
            query = query.where(Role.id != role_id)
        if db.scalar(query) is None:
            return name
        suffix = f"_{index}"
        name = f"{base[:30 - len(suffix)]}{suffix}"
        index += 1


def _set_role_permissions(
    db: Session,
    role: Role,
    permission_codes: list[str],
    enabled_modules: list[str],
) -> None:
    allowed_codes = _allowed_permission_codes(db, enabled_modules)
    requested = set(permission_codes)
    invalid = requested - allowed_codes
    if invalid:
        raise HTTPException(
            status_code=403,
            detail="O perfil possui permissões de módulos não liberados no plano.",
        )
    permissions = db.scalars(
        select(Permission).where(Permission.code.in_(requested))
    ).all()
    db.execute(delete(RolePermission).where(RolePermission.role_id == role.id))
    db.flush()
    for permission in permissions:
        db.add(RolePermission(role_id=role.id, permission_id=permission.id))


def _role_can_be_changed(role: Role) -> None:
    if role.name in _SYSTEM_ROLES:
        raise HTTPException(
            status_code=400,
            detail="Perfil do sistema não pode ser alterado.",
        )


@router.get("/users", response_model=list[UserRead])
def list_users(
    role: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("users:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> list[UserRead]:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    query = select(User).where(User.email.notin_(_SYSTEM_USER_EMAILS)).order_by(User.name)
    if role is not None:
        query = query.where(User.role == role)
    return [
        serialize_user(db, user, enabled_modules)
        for user in db.scalars(query).all()
    ]


@router.post("/users", response_model=UserRead, status_code=status.HTTP_201_CREATED)
def create_user(
    user_in: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("users:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> UserRead:
    email = user_in.email.lower()
    company_code = _company_code_from_credentials(credentials)
    require_duplicate_authorization(
        email,
        company_code,
        user_in.allow_cross_company_duplicate,
    )
    if db.scalar(select(User).where(User.email == email)) is not None:
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado.")

    enforce_user_limit(db, company_code, activating_new_user=user_in.active)

    if db.scalar(select(Role).where(Role.name == user_in.role, Role.active.is_(True))) is None:
        raise HTTPException(status_code=400, detail="Perfil invalido.")
    seller_code = normalize_seller_code(user_in.seller_code)
    if seller_code is not None and db.scalar(select(User).where(User.seller_code == seller_code)) is not None:
        raise HTTPException(status_code=409, detail="Codigo de vendedor ja cadastrado.")

    user = User(
        name=user_in.name,
        email=email,
        seller_code=seller_code,
        password_hash=hash_password(user_in.password),
        must_change_password=True,
        role=user_in.role,
        active=user_in.active,
    )
    db.add(user)
    db.flush()
    _set_user_app_access(db, user, user_in.app_access)
    db.commit()
    db.refresh(user)
    upsert_user_index(
        company_code=company_code,
        company_name=company_name_for_code(company_code),
        user_id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        active=user.active,
    )
    return serialize_user(db, user, _enabled_modules_from_credentials(credentials))


@router.get("/users/{user_id}", response_model=UserRead)
def get_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("users:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> UserRead:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado.")
    return serialize_user(db, user, _enabled_modules_from_credentials(credentials))


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(
    user_id: int,
    user_in: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("users:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> UserRead:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado.")

    update_data = user_in.model_dump(exclude_unset=True)
    allow_cross_company_duplicate = bool(
        update_data.pop("allow_cross_company_duplicate", False)
    )
    app_access = update_data.pop("app_access", None)
    old_email = user.email
    company_code = _company_code_from_credentials(credentials)
    if "email" in update_data:
        email = update_data["email"].lower()
        require_duplicate_authorization(
            email,
            company_code,
            allow_cross_company_duplicate,
        )
        existing = db.scalar(select(User).where(User.email == email, User.id != user_id))
        if existing is not None:
            raise HTTPException(status_code=409, detail="E-mail ja cadastrado.")
        user.email = email
        update_data.pop("email")

    if "role" in update_data:
        if db.scalar(select(Role).where(Role.name == update_data["role"], Role.active.is_(True))) is None:
            raise HTTPException(status_code=400, detail="Perfil invalido.")
    if update_data.get("active") is True and not user.active:
        enforce_user_limit(db, company_code, activating_new_user=True)
    if "seller_code" in update_data:
        seller_code = normalize_seller_code(update_data.pop("seller_code"))
        if seller_code is not None:
            existing_code = db.scalar(
                select(User).where(User.seller_code == seller_code, User.id != user_id)
            )
            if existing_code is not None:
                raise HTTPException(status_code=409, detail="Codigo de vendedor ja cadastrado.")
        user.seller_code = seller_code

    if "password" in update_data:
        user.password_hash = hash_password(update_data.pop("password"))
        user.must_change_password = True
        user.password_changed_at = None

    for field, value in update_data.items():
        setattr(user, field, value)

    _set_user_app_access(db, user, app_access)
    db.commit()
    db.refresh(user)
    if old_email != user.email:
        remove_user_index(company_code, old_email)
    upsert_user_index(
        company_code=company_code,
        company_name=company_name_for_code(company_code),
        user_id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        active=user.active,
    )
    return serialize_user(db, user, _enabled_modules_from_credentials(credentials))


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("users:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> None:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")
    if user.id == current_user.id:
        raise HTTPException(
            status_code=400,
            detail="Você não pode excluir o próprio usuário logado.",
        )
    if user.role == "admin":
        raise HTTPException(
            status_code=400,
            detail="Usuário administrador não pode ser excluído.",
        )
    company_code = _company_code_from_credentials(credentials)
    remove_user_index(company_code, user.email)
    db.delete(user)
    db.commit()


def _company_code_from_credentials(
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Token de acesso ausente.")
    payload = decode_access_token(credentials.credentials)
    company_code = payload.get("company_code")
    if not isinstance(company_code, str) or not company_code:
        raise HTTPException(status_code=401, detail="Token sem empresa.")
    return company_code


def normalize_seller_code(value: str | None) -> str | None:
    code = (value or "").strip().upper()
    return code or None


@router.get("/roles", response_model=list[RoleRead])
def list_roles(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("users:manage", "permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> list[RoleRead]:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    roles = db.scalars(
        select(Role)
        .where(Role.active.is_(True), Role.name.notin_(_LEGACY_ROLES))
        .order_by(Role.label)
    ).all()
    return [serialize_role(db, role, enabled_modules) for role in roles]


@router.post("/roles", response_model=RoleRead, status_code=status.HTTP_201_CREATED)
def create_role(
    role_in: RoleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> RoleRead:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    role = Role(
        name=_unique_role_name(db, role_in.label),
        label=role_in.label.strip(),
        description=(role_in.description or "").strip() or None,
        active=role_in.active,
    )
    db.add(role)
    db.flush()
    _set_role_permissions(db, role, role_in.permissions, enabled_modules)
    db.commit()
    db.refresh(role)
    return serialize_role(db, role, enabled_modules)


@router.put("/roles/{role_id}", response_model=RoleRead)
def update_role(
    role_id: int,
    role_in: RoleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> RoleRead:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    role = db.get(Role, role_id)
    if role is None or role.name in _LEGACY_ROLES:
        raise HTTPException(status_code=404, detail="Perfil não encontrado.")
    _role_can_be_changed(role)

    update_data = role_in.model_dump(exclude_unset=True)
    if "label" in update_data and update_data["label"] is not None:
        role.label = update_data["label"].strip()
    if "description" in update_data:
        role.description = (update_data["description"] or "").strip() or None
    if "active" in update_data and update_data["active"] is not None:
        role.active = update_data["active"]
    if role_in.permissions is not None:
        _set_role_permissions(db, role, role_in.permissions, enabled_modules)

    db.commit()
    db.refresh(role)
    return serialize_role(db, role, enabled_modules)


@router.delete("/roles/{role_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_role(
    role_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("permissions:manage")),
) -> None:
    role = db.get(Role, role_id)
    if role is None or role.name in _LEGACY_ROLES:
        raise HTTPException(status_code=404, detail="Perfil não encontrado.")
    _role_can_be_changed(role)
    if db.scalar(select(User).where(User.role == role.name)) is not None:
        raise HTTPException(
            status_code=409,
            detail="Este perfil está em uso por um usuário.",
        )
    db.delete(role)
    db.commit()


@router.get("/permissions", response_model=list[PermissionRead])
def list_permissions(
    module: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> list[Permission]:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    query = select(Permission).order_by(Permission.module, Permission.label)
    if module is not None:
        query = query.where(Permission.module == module)
    return [
        permission
        for permission in db.scalars(query).all()
        if permission_allowed_by_modules(permission.code, enabled_modules)
    ]


@router.put("/users/{user_id}/permissions", response_model=UserRead)
def set_user_permission(
    user_id: int,
    permission_in: UserPermissionSet,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> UserRead:
    enabled_modules = _enabled_modules_from_credentials(credentials)
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado.")

    permission = db.scalar(
        select(Permission).where(Permission.code == permission_in.permission_code)
    )
    if permission is None:
        raise HTTPException(status_code=404, detail="Permissao nao encontrada.")
    _ensure_permission_allowed(permission.code, enabled_modules)

    user_permission = db.scalar(
        select(UserPermission).where(
            UserPermission.user_id == user.id,
            UserPermission.permission_id == permission.id,
        )
    )
    if user_permission is None:
        user_permission = UserPermission(
            user_id=user.id,
            permission_id=permission.id,
            allowed=permission_in.allowed,
        )
        db.add(user_permission)
    else:
        user_permission.allowed = permission_in.allowed

    db.commit()
    db.refresh(user)
    return serialize_user(db, user, enabled_modules)

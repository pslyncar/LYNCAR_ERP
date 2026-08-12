from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.permissions import DEFAULT_ROLES, PERMISSIONS, ROLE_PERMISSION_CODES
from app.models.access_control import Permission, Role, RolePermission, UserPermission
from app.models.user import User


def seed_default_access_control(db: Session) -> None:
    roles_by_name: dict[str, Role] = {}
    for role_name, role_data in DEFAULT_ROLES.items():
        role = db.scalar(select(Role).where(Role.name == role_name))
        if role is None:
            role = Role(
                name=role_name,
                label=role_data["label"],
                description=role_data["description"],
                active=True,
            )
            db.add(role)
        else:
            role.label = role_data["label"]
            role.description = role_data["description"]
            role.active = True
        roles_by_name[role_name] = role

    permissions_by_code: dict[str, Permission] = {}
    for permission_data in PERMISSIONS:
        permission = db.scalar(
            select(Permission).where(Permission.code == permission_data.code)
        )
        if permission is None:
            permission = Permission(
                code=permission_data.code,
                label=permission_data.label,
                module=permission_data.module,
                description=permission_data.description,
                active=True,
            )
            db.add(permission)
        else:
            permission.label = permission_data.label
            permission.module = permission_data.module
            permission.description = permission_data.description
            permission.active = True
        permissions_by_code[permission_data.code] = permission

    db.flush()

    for role_name, permission_codes in ROLE_PERMISSION_CODES.items():
        role = roles_by_name[role_name]
        desired_permission_ids = {
            permissions_by_code[permission_code].id
            for permission_code in permission_codes
        }
        existing_permissions = db.scalars(
            select(RolePermission).where(RolePermission.role_id == role.id)
        ).all()
        for existing in existing_permissions:
            if existing.permission_id not in desired_permission_ids:
                db.delete(existing)
        for permission_code in permission_codes:
            permission = permissions_by_code[permission_code]
            existing = db.scalar(
                select(RolePermission).where(
                    RolePermission.role_id == role.id,
                    RolePermission.permission_id == permission.id,
                )
            )
            if existing is None:
                db.add(RolePermission(role_id=role.id, permission_id=permission.id))

    db.commit()


def get_user_permission_codes(
    db: Session,
    user: User,
    enabled_modules: list[str] | None = None,
) -> set[str]:
    role_permission_codes = set(
        db.scalars(
            select(Permission.code)
            .join(RolePermission, RolePermission.permission_id == Permission.id)
            .join(Role, Role.id == RolePermission.role_id)
            .where(Role.name == user.role, Role.active.is_(True), Permission.active.is_(True))
        ).all()
    )

    overrides = db.execute(
        select(Permission.code, UserPermission.allowed)
        .join(UserPermission, UserPermission.permission_id == Permission.id)
        .where(
            UserPermission.user_id == user.id,
            Permission.active.is_(True),
        )
    ).all()

    for permission_code, allowed in overrides:
        if allowed:
            role_permission_codes.add(permission_code)
        else:
            role_permission_codes.discard(permission_code)

    if enabled_modules is not None:
        from app.services.company_modules import permission_allowed_by_modules

        role_permission_codes = {
            code
            for code in role_permission_codes
            if permission_allowed_by_modules(code, enabled_modules)
        }

    return role_permission_codes


def user_has_permission(db: Session, user: User, permission_code: str) -> bool:
    if user.role == "admin":
        return True
    return permission_code in get_user_permission_codes(db, user)


def user_has_configured_permission(
    db: Session,
    user: User,
    permission_code: str,
) -> bool:
    return permission_code in get_user_permission_codes(db, user)

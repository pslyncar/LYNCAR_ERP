from dataclasses import dataclass
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.services.tenancy import get_company_by_code, normalize_company_code


@dataclass(frozen=True)
class PlanLimits:
    code: str
    name: str
    monthly_price: str | None
    annual_price: str | None
    max_users: int | None
    database_limit_mb: int
    file_limit_mb: int
    multi_company_limit: int | None
    api_enabled: bool
    priority_support: bool
    default_modules: list[str]


PLAN_LIMITS: dict[str, PlanLimits] = {
    "start": PlanLimits(
        "start",
        "Start",
        "59,90",
        "599,00",
        5,
        80,
        1536,
        1,
        False,
        False,
        [
            "dashboard",
            "clients",
            "products",
            "stock",
            "stock_entries",
            "stock_withdrawals",
            "suppliers",
            "sales",
            "cash_closings",
            "pdv",
            "reports",
            "finance",
            "support",
            "settings",
            "users",
            "permissions",
        ],
    ),
    "pro": PlanLimits(
        "pro",
        "Pro",
        "119,90",
        "1.199,00",
        25,
        250,
        4096,
        3,
        True,
        False,
        [
            "dashboard",
            "clients",
            "products",
            "stock",
            "stock_entries",
            "stock_withdrawals",
            "suppliers",
            "production",
            "service_contracts",
            "sales",
            "cash_closings",
            "pdv",
            "pdv_windows",
            "service_orders",
            "tickets",
            "reports",
            "finance",
            "fiscal",
            "support",
            "settings",
            "users",
            "permissions",
        ],
    ),
    "business": PlanLimits(
        "business",
        "Business",
        "279,90",
        "2.799,00",
        100,
        2048,
        8192,
        5,
        True,
        True,
        [
            "dashboard",
            "clients",
            "products",
            "stock",
            "stock_entries",
            "stock_withdrawals",
            "suppliers",
            "production",
            "service_contracts",
            "sales",
            "cash_closings",
            "pdv",
            "pdv_windows",
            "service_orders",
            "equipments",
            "tickets",
            "monitoring",
            "reports",
            "finance",
            "fiscal",
            "support",
            "settings",
            "users",
            "permissions",
        ],
    ),
    "enterprise": PlanLimits(
        "enterprise",
        "Enterprise",
        None,
        None,
        None,
        5120,
        51200,
        None,
        True,
        True,
        [
            "dashboard",
            "clients",
            "products",
            "stock",
            "stock_entries",
            "stock_withdrawals",
            "suppliers",
            "production",
            "service_contracts",
            "sales",
            "cash_closings",
            "pdv",
            "pdv_windows",
            "service_orders",
            "equipments",
            "tickets",
            "monitoring",
            "reports",
            "finance",
            "fiscal",
            "support",
            "settings",
            "users",
            "permissions",
        ],
    ),
}


def normalize_plan_code(value: str | None) -> str:
    code = (value or "start").strip().lower()
    aliases = {"starter": "start", "erp": "start", "premium": "business"}
    return aliases.get(code, code if code in PLAN_LIMITS else "start")


def plan_defaults(plan_code: str | None) -> PlanLimits:
    code = normalize_plan_code(plan_code)
    with MasterSessionLocal() as db:
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == code))
        if plan is not None:
            return PlanLimits(
                code=plan.code,
                name=plan.name,
                monthly_price=plan.monthly_price,
                annual_price=plan.annual_price,
                max_users=plan.max_users,
                database_limit_mb=plan.database_limit_mb,
                file_limit_mb=plan.file_limit_mb,
                multi_company_limit=plan.multi_company_limit,
                api_enabled=plan.api_enabled,
                priority_support=plan.priority_support,
                default_modules=list(plan.default_modules or []),
            )
    return PLAN_LIMITS[code]


def seed_subscription_plans(db: Session) -> None:
    has_any_plan = db.scalar(select(SubscriptionPlan.id).limit(1))
    if has_any_plan is not None:
        return
    for index, default in enumerate(PLAN_LIMITS.values(), start=1):
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == default.code))
        if plan is None:
            db.add(
                SubscriptionPlan(
                    code=default.code,
                    name=default.name,
                    monthly_price=default.monthly_price,
                    annual_price=default.annual_price,
                    max_users=default.max_users,
                    database_limit_mb=default.database_limit_mb,
                    file_limit_mb=default.file_limit_mb,
                    multi_company_limit=default.multi_company_limit,
                    api_enabled=default.api_enabled,
                    priority_support=default.priority_support,
                    default_modules=list(default.default_modules),
                    active=True,
                    sort_order=index * 10,
                )
            )
        elif not plan.default_modules:
            plan.default_modules = list(default.default_modules)
        elif default.code != "start" and "pdv" in plan.default_modules and "pdv_windows" not in plan.default_modules:
            plan.default_modules = sorted([*plan.default_modules, "pdv_windows"])


def effective_plan_limits(company: Company | None) -> dict[str, Any]:
    base = plan_defaults(company.plan if company else "enterprise")
    result: dict[str, Any] = {
        "plan": base.code,
        "plan_name": base.name,
        "monthly_price": base.monthly_price,
        "annual_price": base.annual_price,
        "max_users": base.max_users,
        "database_limit_mb": base.database_limit_mb,
        "file_limit_mb": base.file_limit_mb,
        "multi_company_limit": base.multi_company_limit,
        "api_enabled": base.api_enabled,
        "priority_support": base.priority_support,
        "default_modules": list(base.default_modules),
    }
    overrides = company.plan_overrides if company else None
    if isinstance(overrides, dict):
        for key in (
            "max_users",
            "database_limit_mb",
            "file_limit_mb",
            "multi_company_limit",
            "api_enabled",
            "priority_support",
        ):
            if key in overrides and overrides[key] not in ("", None):
                result[key] = overrides[key]
    return result


def company_plan_limits(company_code: str) -> dict[str, Any]:
    company = get_company_by_code(company_code)
    return effective_plan_limits(company)


def enforce_user_limit(db: Session, company_code: str, *, activating_new_user: bool) -> None:
    if not activating_new_user:
        return
    limits = company_plan_limits(company_code)
    max_users = limits.get("max_users")
    if max_users in (None, "", 0):
        return
    active_users = db.scalar(select(func.count(User.id)).where(User.active.is_(True))) or 0
    if active_users >= int(max_users):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Limite de usuarios do plano {limits['plan_name']} atingido "
                f"({active_users}/{max_users}). Ajuste o plano no master para liberar mais usuarios."
            ),
        )


def tenant_file_usage_bytes(company_code: str, upload_root: Path) -> int:
    scope = f"tenant-products-{normalize_company_code(company_code)}"
    target_dir = upload_root / scope
    if not target_dir.exists():
        return 0
    return sum(path.stat().st_size for path in target_dir.rglob("*") if path.is_file())


def enforce_file_limit(company_code: str, upload_root: Path, incoming_bytes: int) -> None:
    limits = company_plan_limits(company_code)
    limit_mb = limits.get("file_limit_mb")
    if limit_mb in (None, "", 0):
        return
    limit_bytes = int(limit_mb) * 1024 * 1024
    used = tenant_file_usage_bytes(company_code, upload_root)
    if used + incoming_bytes > limit_bytes:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Limite de arquivos do plano {limits['plan_name']} atingido. "
                "Aumente o plano ou libere espaco antes de enviar novos arquivos."
            ),
        )


def current_database_size_mb(db: Session) -> int:
    size_bytes = db.scalar(text("SELECT pg_database_size(current_database())")) or 0
    return int(int(size_bytes) / 1024 / 1024)


def enforce_database_limit(db: Session, company_code: str) -> None:
    limits = company_plan_limits(company_code)
    limit_mb = limits.get("database_limit_mb")
    if limit_mb in (None, "", 0):
        return
    current_mb = current_database_size_mb(db)
    if current_mb >= int(limit_mb):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Limite de dados do plano {limits['plan_name']} atingido "
                f"({current_mb} MB/{limit_mb} MB). Ajuste o plano no master para continuar gravando."
            ),
        )

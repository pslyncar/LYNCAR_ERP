from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select, text
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.business_segment import BusinessSegment
from app.models.company import Company
from app.models.pdv_terminal import PdvTerminal
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
    max_pdv_terminals: int | None
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
        None,
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
        None,
        250,
        4096,
        3,
        True,
        False,
        [
            "dashboard",
            "clients",
            "products",
            "product_promotions",
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
        None,
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
            "product_promotions",
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
    return aliases.get(code, code)


def maximum_configured_limit(*values: object) -> int | None:
    configured = [int(value) for value in values if value not in (None, "", 0)]
    return max(configured) if configured else None


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
                max_pdv_terminals=plan.max_pdv_terminals,
                database_limit_mb=plan.database_limit_mb,
                file_limit_mb=plan.file_limit_mb,
                multi_company_limit=plan.multi_company_limit,
                api_enabled=plan.api_enabled,
                priority_support=plan.priority_support,
                default_modules=list(plan.default_modules or []),
            )
        has_any_plan = db.scalar(select(SubscriptionPlan.id).limit(1))
    if has_any_plan is None and code in PLAN_LIMITS:
        return PLAN_LIMITS[code]
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=f"Plano '{code}' nao encontrado no banco master.",
    )


def effective_plan_limits(company: Company | None) -> dict[str, Any]:
    base = plan_defaults(company.plan if company else "enterprise")
    result: dict[str, Any] = {
        "plan": base.code,
        "plan_name": base.name,
        "monthly_price": base.monthly_price,
        "annual_price": base.annual_price,
        "max_users": base.max_users,
        "max_pdv_terminals": base.max_pdv_terminals,
        "database_limit_mb": base.database_limit_mb,
        "file_limit_mb": base.file_limit_mb,
        "multi_company_limit": base.multi_company_limit,
        "api_enabled": base.api_enabled,
        "priority_support": base.priority_support,
        "default_modules": list(base.default_modules),
    }
    segment = None
    if company is not None:
        with MasterSessionLocal() as db:
            segment = db.scalar(
                select(BusinessSegment).where(BusinessSegment.code == company.business_type)
            )
    overrides = company.plan_overrides if company else None
    if isinstance(overrides, dict):
        for key in (
            "database_limit_mb",
            "file_limit_mb",
            "multi_company_limit",
            "api_enabled",
            "priority_support",
        ):
            if key in overrides and overrides[key] not in ("", None):
                result[key] = overrides[key]
    for key in ("max_users", "max_pdv_terminals"):
        candidates = [result.get(key)]
        if segment is not None:
            candidates.append(getattr(segment, key, None))
        if isinstance(overrides, dict):
            candidates.append(overrides.get(key))
        result[key] = maximum_configured_limit(*candidates)
    return result


def company_plan_limits(company_code: str) -> dict[str, Any]:
    company = get_company_by_code(company_code)
    return effective_plan_limits(company)


def _lock_quota_check(db: Session, company_code: str, resource: str) -> None:
    """Serializa criacoes concorrentes no PostgreSQL sem exigir outro broker."""
    if db.get_bind().dialect.name != "postgresql":
        return
    db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:quota_key))"),
        {"quota_key": f"lyncar:{normalize_company_code(company_code)}:{resource}"},
    )


def lock_pdv_terminal_quota(db: Session, company_code: str) -> None:
    _lock_quota_check(db, company_code, "pdv-terminals")


def company_resource_usage(db: Session, company_code: str) -> dict[str, Any]:
    limits = company_plan_limits(company_code)
    active_users = db.scalar(
        select(func.count(User.id)).where(
            User.active.is_(True),
            User.email != "_pdv_terminal@lyncar.local",
        )
    ) or 0
    pdv_terminals = db.scalar(_licensed_pdv_terminals_count_query()) or 0
    return {
        "company_code": normalize_company_code(company_code),
        "active_users": int(active_users),
        "max_users": limits.get("max_users"),
        "pdv_terminals": int(pdv_terminals),
        "max_pdv_terminals": limits.get("max_pdv_terminals"),
    }


def enforce_user_limit(db: Session, company_code: str, *, activating_new_user: bool) -> None:
    if not activating_new_user:
        return
    _lock_quota_check(db, company_code, "users")
    limits = company_plan_limits(company_code)
    max_users = limits.get("max_users")
    if max_users in (None, "", 0):
        return
    active_users = db.scalar(
        select(func.count(User.id)).where(
            User.active.is_(True),
            User.email != "_pdv_terminal@lyncar.local",
        )
    ) or 0
    if active_users >= int(max_users):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Limite de usuarios do cliente atingido ({active_users}/{max_users}). "
                "Aumente o limite no plano, segmento ou cadastro exclusivo da empresa no MASTER."
            ),
        )


def enforce_pdv_terminal_limit(
    db: Session,
    company_code: str,
    *,
    adding_new_terminal: bool,
) -> None:
    if not adding_new_terminal:
        return
    _lock_quota_check(db, company_code, "pdv-terminals")
    limits = company_plan_limits(company_code)
    max_terminals = limits.get("max_pdv_terminals")
    if max_terminals in (None, "", 0):
        return
    terminals = db.scalar(_licensed_pdv_terminals_count_query()) or 0
    if terminals >= int(max_terminals):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Limite de PDVs do cliente atingido "
                f"({terminals}/{max_terminals}). Aumente o limite no plano, "
                "segmento ou cadastro exclusivo da empresa no MASTER."
            ),
        )


def _licensed_pdv_terminals_count_query():
    now = datetime.now(UTC)
    return select(func.count(PdvTerminal.id)).where(
        or_(
            PdvTerminal.activation_status != "pending",
            PdvTerminal.activation_code_expires_at >= now,
        )
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

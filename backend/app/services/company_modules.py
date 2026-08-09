from app.core.permissions import PERMISSIONS
from app.core.master_database import MasterSessionLocal
from app.models.subscription_plan import SubscriptionPlan

ALL_MODULES = [
    "dashboard",
    "clients",
    "products",
    "stock",
    "suppliers",
    "production",
    "service_contracts",
    "sales",
    "pdv",
    "pdv_windows",
    "service_orders",
    "equipments",
    "tickets",
    "monitoring",
    "reports",
    "finance",
    "fiscal",
    "users",
    "permissions",
]

BUSINESS_TYPE_MODULES = {
    "assistencia_papezzo": ALL_MODULES,
    "assistencia_tecnica": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "sales",
        "pdv",
        "service_orders",
        "tickets",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "mercado": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "sales",
        "pdv",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "padaria": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "production",
        "sales",
        "pdv",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "loja": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "sales",
        "pdv",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "custom": ALL_MODULES,
}

PERMISSION_MODULES = {permission.code: permission.module for permission in PERMISSIONS}

PLAN_ORDER = {"start": 0, "pro": 1, "business": 2, "enterprise": 3}
MODULE_MIN_PLAN = {
}


PLAN_DEFAULT_MODULES = {
    "start": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "sales",
        "pdv",
        "reports",
        "finance",
        "users",
        "permissions",
    ],
    "pro": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "production",
        "service_contracts",
        "sales",
        "pdv",
        "pdv_windows",
        "service_orders",
        "tickets",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "business": [
        "dashboard",
        "clients",
        "products",
        "stock",
        "suppliers",
        "production",
        "service_contracts",
        "sales",
        "pdv",
        "pdv_windows",
        "service_orders",
        "equipments",
        "tickets",
        "monitoring",
        "reports",
        "finance",
        "fiscal",
        "users",
        "permissions",
    ],
    "enterprise": ALL_MODULES,
}


def _normalize_plan(value: str | None) -> str:
    code = (value or "start").strip().lower()
    aliases = {"starter": "start", "erp": "start", "premium": "business"}
    return aliases.get(code, code)


def plan_default_modules(plan_code: str | None) -> list[str]:
    normalized = _normalize_plan(plan_code)
    try:
        with MasterSessionLocal() as db:
            plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.code == normalized).first()
            if plan is not None and plan.default_modules:
                return sorted(set(plan.default_modules))
    except Exception:
        pass
    return sorted(set(PLAN_DEFAULT_MODULES.get(normalized, PLAN_DEFAULT_MODULES["start"])))


def plan_allows_module(plan_code: str | None, module: str) -> bool:
    required = MODULE_MIN_PLAN.get(module)
    if required is None:
        return True
    normalized = _normalize_plan(plan_code)
    return PLAN_ORDER.get(normalized, 0) >= PLAN_ORDER[required]


def filter_modules_by_plan(modules: list[str], plan_code: str | None) -> list[str]:
    return sorted(module for module in modules if plan_allows_module(plan_code, module))


def modules_for_business_type(
    business_type: str,
    modules: list[str] | None,
    plan_code: str | None = None,
) -> list[str]:
    plan_modules = set(plan_default_modules(plan_code))
    if modules:
        enabled = set(modules)
        if "stock" in enabled:
            enabled.add("suppliers")
        return sorted(module for module in enabled if module in ALL_MODULES)
    enabled = set(BUSINESS_TYPE_MODULES.get(business_type, BUSINESS_TYPE_MODULES["custom"]))
    return filter_modules_by_plan(sorted(enabled & plan_modules), plan_code)


def permission_allowed_by_modules(permission_code: str, enabled_modules: list[str]) -> bool:
    module = PERMISSION_MODULES.get(permission_code)
    return module is None or module in enabled_modules

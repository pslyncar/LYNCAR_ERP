from app.core.permissions import PERMISSIONS
from app.core.master_database import MasterSessionLocal
from app.models.business_segment import BusinessSegment
from app.models.subscription_plan import SubscriptionPlan

ALL_MODULES = [
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
]

BUSINESS_TYPE_MODULES = {
    "assistencia_papezzo": ALL_MODULES,
    "assistencia_tecnica": [
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
    "mercado": [
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
            "fiscal",
            "support",
            "settings",
            "users",
        "permissions",
    ],
    "padaria": [
        "dashboard",
        "clients",
        "products",
            "stock",
            "stock_entries",
            "stock_withdrawals",
            "suppliers",
        "production",
            "sales",
            "cash_closings",
            "pdv",
        "reports",
        "finance",
            "fiscal",
            "support",
            "settings",
            "users",
        "permissions",
    ],
    "loja": [
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
            "fiscal",
            "support",
            "settings",
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
    "pro": [
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
    "business": [
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
    "enterprise": ALL_MODULES,
}

SEGMENT_DEFAULTS = {
    "assistencia_papezzo": {
        "name": "Assistencia Papezzo com monitoramento",
        "description": "Assistencia tecnica completa, contratos, maquinas e monitoramento.",
        "default_modules": BUSINESS_TYPE_MODULES["assistencia_papezzo"],
        "sort_order": 10,
    },
    "assistencia_tecnica": {
        "name": "Assistencia tecnica",
        "description": "Atendimento tecnico com OS, chamados, estoque e financeiro.",
        "default_modules": BUSINESS_TYPE_MODULES["assistencia_tecnica"],
        "sort_order": 20,
    },
    "mercado": {
        "name": "Mercado",
        "description": "Operacao de vendas, estoque, fornecedores, fiscal e PDV.",
        "default_modules": BUSINESS_TYPE_MODULES["mercado"],
        "sort_order": 30,
    },
    "padaria": {
        "name": "Padaria",
        "description": "Vendas, estoque, fornecedores, producao, fiscal e PDV.",
        "default_modules": BUSINESS_TYPE_MODULES["padaria"],
        "sort_order": 40,
    },
    "loja": {
        "name": "Loja",
        "description": "Loja comercial com vendas, estoque, financeiro, fiscal e PDV.",
        "default_modules": BUSINESS_TYPE_MODULES["loja"],
        "sort_order": 50,
    },
    "custom": {
        "name": "Personalizado",
        "description": "Segmento livre para clientes fora dos modelos padrao.",
        "default_modules": BUSINESS_TYPE_MODULES["custom"],
        "sort_order": 999,
    },
}


def normalize_modules(modules: list[str] | None) -> list[str]:
    enabled = set(modules or [])
    if "stock" in enabled:
        enabled.add("suppliers")
    return sorted(module for module in enabled if module in ALL_MODULES)


def _normalize_plan(value: str | None) -> str:
    code = (value or "start").strip().lower()
    aliases = {"starter": "start", "erp": "start", "premium": "business"}
    return aliases.get(code, code)


def _normalize_business_type(value: str | None) -> str:
    code = (value or "custom").strip().lower()
    aliases = {"assistencia_técnica": "assistencia_tecnica"}
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


def seed_business_segments(db) -> None:
    has_any_segment = db.query(BusinessSegment.id).first()
    if has_any_segment is not None:
        return
    for code, default in SEGMENT_DEFAULTS.items():
        segment = db.query(BusinessSegment).filter(BusinessSegment.code == code).first()
        if segment is None:
            db.add(
                BusinessSegment(
                    code=code,
                    name=default["name"],
                    description=default["description"],
                    default_modules=list(default["default_modules"]),
                    active=True,
                    sort_order=default["sort_order"],
                )
            )
        elif not segment.default_modules:
            segment.default_modules = list(default["default_modules"])


def segment_default_modules(business_type: str | None) -> list[str]:
    code = _normalize_business_type(business_type)
    try:
        with MasterSessionLocal() as db:
            seed_business_segments(db)
            db.commit()
            segment = db.query(BusinessSegment).filter(BusinessSegment.code == code).first()
            if segment is not None and segment.default_modules:
                return normalize_modules(segment.default_modules)
    except Exception:
        pass
    return normalize_modules(BUSINESS_TYPE_MODULES.get(code, BUSINESS_TYPE_MODULES["custom"]))


def modules_for_business_type(
    business_type: str,
    modules: list[str] | None,
    plan_code: str | None = None,
) -> list[str]:
    plan_modules = set(plan_default_modules(plan_code))
    if modules is not None:
        return normalize_modules(modules)
    enabled = set(segment_default_modules(business_type))
    return filter_modules_by_plan(sorted(enabled & plan_modules), plan_code)


def permission_allowed_by_modules(permission_code: str, enabled_modules: list[str]) -> bool:
    module = PERMISSION_MODULES.get(permission_code)
    return module is None or module in enabled_modules

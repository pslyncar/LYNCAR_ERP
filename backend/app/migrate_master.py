import secrets

from sqlalchemy import func, select, text

from app.core.master_database import MasterBase, MasterSessionLocal, master_engine
from app.models.company import Company  # noqa: F401
from app.models.business_segment import BusinessSegment  # noqa: F401
from app.models.company_billing import CompanyBilling  # noqa: F401
from app.models.dashboard_content import DashboardContent  # noqa: F401
from app.models.company_presence import CompanyPresence  # noqa: F401
from app.models.master_user import MasterUser  # noqa: F401
from app.models.master_support import MasterSupportTicket, MasterSupportMessage  # noqa: F401
from app.models.master_user_index import MasterUserIndex  # noqa: F401
from app.models.master_fiscal_reference import (  # noqa: F401
    MasterIbsCbsClassTrib,
    MasterFiscalCestCode,
    MasterFiscalCfopCode,
    MasterFiscalNcmCode,
    MasterFiscalReferenceSync,
)
from app.models.master_holiday import MasterHoliday, MasterHolidaySync  # noqa: F401
from app.models.payment_setting import PaymentSetting  # noqa: F401
from app.models.pdv_update import (  # noqa: F401
    PdvAppVersion,
    PdvAppVersionRollout,
    PdvTerminalUpdateLog,
)
from app.models.subscription_plan import SubscriptionPlan  # noqa: F401
from app.models.website_contact_request import WebsiteContactRequest  # noqa: F401
from app.services.company_modules import (
    modules_for_business_type,
    plan_allows_module,
    seed_business_segments,
)
from app.services.plan_limits import normalize_plan_code, seed_subscription_plans
from app.services.tenancy import seed_master_identity


COMPANY_COLUMNS = [
    ("business_type", "VARCHAR(60) NOT NULL DEFAULT 'custom'"),
    ("person_type", "VARCHAR(2) NOT NULL DEFAULT 'PF'"),
    ("document_number", "VARCHAR(30)"),
    ("state_registration", "VARCHAR(40)"),
    ("municipal_registration", "VARCHAR(40)"),
    ("trade_name", "VARCHAR(180)"),
    ("contact_name", "VARCHAR(150)"),
    ("responsible_cpf", "VARCHAR(14)"),
    ("responsible_birth_date", "DATE"),
    ("phone", "VARCHAR(40)"),
    ("email", "VARCHAR(180)"),
    ("address_line", "VARCHAR(180)"),
    ("address_number", "VARCHAR(20)"),
    ("neighborhood", "VARCHAR(120)"),
    ("city", "VARCHAR(120)"),
    ("city_code", "VARCHAR(20)"),
    ("state", "VARCHAR(2)"),
    ("zip_code", "VARCHAR(20)"),
    ("tax_regime", "VARCHAR(40)"),
    ("crt", "VARCHAR(10)"),
    ("tax_regime_source", "VARCHAR(80)"),
    ("tax_regime_checked_at", "VARCHAR(30)"),
    ("cnpj_lookup_status", "VARCHAR(40)"),
    ("cnpj_lookup_message", "TEXT"),
    ("cnae_main", "VARCHAR(20)"),
    ("legal_nature", "VARCHAR(120)"),
    ("company_size", "VARCHAR(80)"),
    ("plan_overrides", "JSON"),
    ("monthly_price", "VARCHAR(30)"),
    ("billing_day", "VARCHAR(2)"),
    ("payment_method", "VARCHAR(40)"),
    ("digital_certificate_configured", "BOOLEAN NOT NULL DEFAULT false"),
    ("digital_certificate_name", "VARCHAR(180)"),
    ("digital_certificate_expires_at", "VARCHAR(30)"),
    ("digital_certificate_notes", "TEXT"),
    ("enabled_modules", "JSON NOT NULL DEFAULT '[]'"),
    ("xml_email_token", "VARCHAR(40)"),
    ("xml_email_enabled", "BOOLEAN NOT NULL DEFAULT true"),
    ("business_day_cutoff_minutes", "INTEGER NOT NULL DEFAULT 180"),
]

BILLING_COLUMNS = [
    ("mercado_pago_payment_id", "VARCHAR(80)"),
    ("mercado_pago_status", "VARCHAR(40)"),
    ("mercado_pago_external_reference", "VARCHAR(120)"),
    ("mercado_pago_idempotency_key", "VARCHAR(80)"),
    ("pix_qr_code", "TEXT"),
    ("pix_qr_code_base64", "TEXT"),
    ("pix_ticket_url", "TEXT"),
]

MASTER_USER_COLUMNS = [
    ("must_change_password", "BOOLEAN NOT NULL DEFAULT false"),
    ("password_changed_at", "TIMESTAMP WITH TIME ZONE"),
]

MASTER_HOLIDAY_COLUMNS = [
    ("city_code", "VARCHAR(20)"),
]

MASTER_HOLIDAY_SYNC_COLUMNS = [
    ("city_code", "VARCHAR(20)"),
]

MASTER_SUPPORT_TICKET_COLUMNS = [
    ("customer_attachments_enabled", "BOOLEAN NOT NULL DEFAULT false"),
]

SUBSCRIPTION_PLAN_COLUMNS = [
    ("default_modules", "JSON NOT NULL DEFAULT '[]'"),
]


def column_exists(table_name: str, column_name: str) -> bool:
    with master_engine.connect() as connection:
        result = connection.execute(
            text(
                """
                SELECT 1
                FROM information_schema.columns
                WHERE table_name = :table_name
                  AND column_name = :column_name
                """
            ),
            {"table_name": table_name, "column_name": column_name},
        )
        return result.first() is not None


def main() -> None:
    MasterBase.metadata.create_all(bind=master_engine)
    with master_engine.begin() as connection:
        for column_name, column_type in COMPANY_COLUMNS:
            if not column_exists("companies", column_name):
                connection.execute(
                    text(f"ALTER TABLE companies ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text("ALTER TABLE companies ALTER COLUMN person_type SET DEFAULT 'PF'")
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_xml_email_token
                ON companies(xml_email_token)
                WHERE xml_email_token IS NOT NULL
                """
            )
        )
        for column_name, column_type in BILLING_COLUMNS:
            if not column_exists("company_billings", column_name):
                connection.execute(
                    text(f"ALTER TABLE company_billings ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in MASTER_USER_COLUMNS:
            if not column_exists("master_users", column_name):
                connection.execute(
                    text(f"ALTER TABLE master_users ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in MASTER_HOLIDAY_COLUMNS:
            if not column_exists("master_holidays", column_name):
                connection.execute(
                    text(f"ALTER TABLE master_holidays ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in MASTER_HOLIDAY_SYNC_COLUMNS:
            if not column_exists("master_holiday_syncs", column_name):
                connection.execute(
                    text(f"ALTER TABLE master_holiday_syncs ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in MASTER_SUPPORT_TICKET_COLUMNS:
            if not column_exists("master_support_tickets", column_name):
                connection.execute(
                    text(
                        f"ALTER TABLE master_support_tickets ADD COLUMN {column_name} {column_type}"
                    )
                )
        for column_name, column_type in SUBSCRIPTION_PLAN_COLUMNS:
            if not column_exists("subscription_plans", column_name):
                connection.execute(
                    text(f"ALTER TABLE subscription_plans ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_companies_document_number
                ON companies(document_number)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_companies_responsible_cpf
                ON companies(responsible_cpf)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_company_billings_mp_payment
                ON company_billings(mercado_pago_payment_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_company_billings_mp_reference
                ON company_billings(mercado_pago_external_reference)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_master_holidays_city_code
                ON master_holidays(city_code)
                """
            )
        )
    seed_master_identity()
    seed_dashboard_contents()
    with MasterSessionLocal() as db:
        for company in db.scalars(select(Company)).all():
            if not company.xml_email_token:
                company.xml_email_token = (
                    secrets.token_urlsafe(6).lower().replace("_", "").replace("-", "")
                )
        seed_subscription_plans(db)
        seed_business_segments(db)
        db.commit()
    normalize_existing_company_modules()
    enforce_unique_master_user_emails()
    print("Migracao master aplicada com sucesso.")


def enforce_unique_master_user_emails() -> None:
    with master_engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE master_user_index
                SET email = lower(trim(email))
                WHERE email IS NOT NULL
                """
            )
        )
        connection.execute(
            text(
                """
                DELETE FROM master_user_index a
                USING master_user_index b
                WHERE a.email = b.email
                  AND a.id > b.id
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_master_user_index_email
                ON master_user_index(email)
                """
            )
        )


def normalize_existing_company_modules() -> None:
    with MasterSessionLocal() as db:
        _ensure_sidebar_modules_in_existing_records(db)
        companies = list(db.scalars(select(Company)).all())
        changed = False
        for company in companies:
            modules = set(company.enabled_modules or [])
            plan = normalize_plan_code(company.plan)
            if "stock" in modules and "suppliers" not in modules:
                modules.add("suppliers")
                changed = True
            if plan_allows_module(plan, "service_contracts") and "service_contracts" not in modules:
                modules.add("service_contracts")
                changed = True
            normalized_modules = modules_for_business_type(
                company.business_type,
                sorted(modules),
                plan,
            )
            if normalized_modules != (company.enabled_modules or []):
                company.enabled_modules = normalized_modules
                changed = True
        if changed:
            db.commit()


def _ensure_sidebar_modules_in_existing_records(db) -> None:
    new_modules = {
        "stock_entries",
        "stock_withdrawals",
        "cash_closings",
        "support",
        "settings",
    }
    current_plan_modules = set()
    for plan in db.scalars(select(SubscriptionPlan)).all():
        current_plan_modules.update(plan.default_modules or [])
    if current_plan_modules & new_modules:
        return
    additions_by_base = {
        "stock": {"stock_entries", "stock_withdrawals"},
        "sales": {"cash_closings"},
    }
    always_on = {"support", "settings"}
    for plan in db.scalars(select(SubscriptionPlan)).all():
        modules = set(plan.default_modules or [])
        for base, additions in additions_by_base.items():
            if base in modules:
                modules.update(additions)
        modules.update(always_on)
        if sorted(modules) != (plan.default_modules or []):
            plan.default_modules = sorted(modules)
    for segment in db.scalars(select(BusinessSegment)).all():
        modules = set(segment.default_modules or [])
        for base, additions in additions_by_base.items():
            if base in modules:
                modules.update(additions)
        modules.update(always_on)
        if sorted(modules) != (segment.default_modules or []):
            segment.default_modules = sorted(modules)
    for company in db.scalars(select(Company)).all():
        modules = set(company.enabled_modules or [])
        for base, additions in additions_by_base.items():
            if base in modules:
                modules.update(additions)
        modules.update(always_on)
        if sorted(modules) != (company.enabled_modules or []):
            company.enabled_modules = sorted(modules)


def seed_dashboard_contents() -> None:
    with MasterSessionLocal() as db:
        total = db.scalar(select(func.count(DashboardContent.id))) or 0
        if total:
            return
        db.add_all(
            [
                DashboardContent(
                    content_type="notice",
                    title="Bem-vindo ao Lyncar",
                    description=(
                        "Este espaco recebe avisos, novidades e orientacoes "
                        "publicadas pelo master."
                    ),
                    badge="Aviso",
                    button_label="Ver detalhes",
                    segment="todos",
                    sort_order=10,
                    active=True,
                ),
                DashboardContent(
                    content_type="certificate",
                    title="Certificado Digital A1",
                    description=(
                        "Quando o link comercial estiver configurado, a empresa "
                        "podera comprar o certificado por aqui."
                    ),
                    badge="Fiscal",
                    price_label="A1 para NFC-e/NF-e",
                    button_label="Comprar A1",
                    segment="todos",
                    sort_order=20,
                    active=True,
                ),
            ]
        )
        db.commit()


if __name__ == "__main__":
    main()

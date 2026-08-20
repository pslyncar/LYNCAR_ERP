from urllib.parse import unquote, urlparse

from sqlalchemy import text

from app.core.database import Base, engine
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models import access_control, cash_closing, client, company, equipment, equipment_status, fiscal, fiscal_assistant, marketplace, monitoring, payable, pdv_cash_session, pdv_operator, pdv_sync_event, pdv_terminal, product, product_batch, product_composition, production_order, receivable, sale, service_contract, service_order, stock_entry, stock_movement, supplier, ticket, user, xml_inbox  # noqa: F401
from app.services.access_control import seed_default_access_control
from app.migrate_master import main as migrate_master
from app.services.master_user_index import upsert_user_index
from app.services.tenancy import seed_default_company
from app.services.uploads import UPLOAD_ROOT, safe_scope_name


CLIENT_COLUMNS = [
    ("person_type", "VARCHAR(2) NOT NULL DEFAULT 'PF'"),
    ("trade_name", "VARCHAR(180)"),
    ("document_number", "VARCHAR(30)"),
    ("state_registration", "VARCHAR(40)"),
    ("municipal_registration", "VARCHAR(40)"),
    ("tax_contributor_type", "VARCHAR(20)"),
    ("city_code", "VARCHAR(20)"),
    ("country_code", "VARCHAR(4)"),
    ("country_name", "VARCHAR(80)"),
    ("suframa", "VARCHAR(20)"),
    ("contact_person", "VARCHAR(150)"),
    ("mobile_phone", "VARCHAR(40)"),
    ("secondary_email", "VARCHAR(180)"),
    ("address_number", "VARCHAR(20)"),
    ("address_complement", "VARCHAR(120)"),
    ("neighborhood", "VARCHAR(120)"),
    ("city", "VARCHAR(120)"),
    ("state", "VARCHAR(2)"),
    ("zip_code", "VARCHAR(20)"),
    ("monthly_fee", "NUMERIC(12, 2) NOT NULL DEFAULT 0"),
    ("monthly_due_day", "INTEGER"),
    ("allow_credit", "BOOLEAN NOT NULL DEFAULT false"),
    ("credit_limit", "NUMERIC(12, 2) NOT NULL DEFAULT 0"),
    ("credit_status", "VARCHAR(30) NOT NULL DEFAULT 'liberado'"),
    ("payment_terms", "VARCHAR(80)"),
    ("billing_notes", "TEXT"),
]

EQUIPMENT_COLUMNS = [
    ("asset_tag", "VARCHAR(80)"),
    ("location", "VARCHAR(120)"),
    ("responsible_user", "VARCHAR(150)"),
    ("agent_version", "VARCHAR(40)"),
    ("last_ip_address", "VARCHAR(60)"),
    ("last_logged_user", "VARCHAR(150)"),
]

ALERT_COLUMNS = [
    ("metric_value", "NUMERIC(5, 2) NOT NULL DEFAULT 0"),
]

EQUIPMENT_CURRENT_STATUS_COLUMNS = [
    ("storage_volumes", "JSON NOT NULL DEFAULT '[]'"),
]

SERVICE_ORDER_COLUMNS = [
    ("received_equipment", "VARCHAR(180)"),
    ("waiting_reason", "VARCHAR(220)"),
    ("opened_by_user_id", "INTEGER REFERENCES users(id) ON DELETE SET NULL"),
    ("sold_by_user_id", "INTEGER REFERENCES users(id) ON DELETE SET NULL"),
]

PRODUCT_COLUMNS = [
    ("barcode", "VARCHAR(80)"),
    ("image_url", "TEXT"),
    ("brand", "VARCHAR(100)"),
    ("model", "VARCHAR(100)"),
    ("category", "VARCHAR(100)"),
    ("stock_location", "VARCHAR(120)"),
    ("tracks_batch", "BOOLEAN NOT NULL DEFAULT false"),
    ("initial_batch_number", "VARCHAR(80)"),
    ("initial_expiration_date", "DATE"),
    ("offer_price", "NUMERIC(12, 4)"),
    ("offer_start_at", "TIMESTAMP WITH TIME ZONE"),
    ("offer_end_at", "TIMESTAMP WITH TIME ZONE"),
    ("purchase_total_cost", "NUMERIC(12, 2)"),
    ("purchase_quantity", "NUMERIC(12, 3)"),
    ("purchase_conversion_enabled", "BOOLEAN NOT NULL DEFAULT false"),
    ("purchase_invoice_unit", "VARCHAR(20)"),
    ("purchase_package_factor", "NUMERIC(12, 4)"),
    ("purchase_package_barcode", "VARCHAR(80)"),
    ("average_cost", "NUMERIC(12, 4)"),
    ("stock_value", "NUMERIC(14, 4) NOT NULL DEFAULT 0"),
    ("margin_percent", "NUMERIC(7, 2)"),
    ("fiscal_received_quantity", "NUMERIC(12, 3) NOT NULL DEFAULT 0"),
    ("fiscal_issued_quantity", "NUMERIC(12, 3) NOT NULL DEFAULT 0"),
    ("fiscal_available_quantity", "NUMERIC(12, 3) NOT NULL DEFAULT 0"),
    ("fiscal_entry_count", "INTEGER NOT NULL DEFAULT 0"),
    ("ncm", "VARCHAR(20)"),
    ("cest", "VARCHAR(20)"),
    ("cfop_sale", "VARCHAR(10)"),
    ("origin", "VARCHAR(2)"),
    ("cst", "VARCHAR(10)"),
    ("csosn", "VARCHAR(10)"),
    ("icms_rate", "NUMERIC(7, 4)"),
    ("pis_rate", "NUMERIC(7, 4)"),
    ("cofins_rate", "NUMERIC(7, 4)"),
    ("ipi_rate", "NUMERIC(7, 4)"),
    ("iss_rate", "NUMERIC(7, 4)"),
    ("municipal_service_code", "VARCHAR(40)"),
    ("tax_rate", "NUMERIC(7, 4)"),
    ("fiscal_notes", "TEXT"),
    ("ibs_cbs_cst", "VARCHAR(10)"),
    ("ibs_cbs_classification", "VARCHAR(20)"),
    ("cbs_rate", "NUMERIC(7, 4)"),
    ("ibs_state_rate", "NUMERIC(7, 4)"),
    ("ibs_city_rate", "NUMERIC(7, 4)"),
    ("selective_tax_cst", "VARCHAR(10)"),
    ("selective_tax_classification", "VARCHAR(20)"),
    ("selective_tax_rate", "NUMERIC(7, 4)"),
    ("new_tax_system", "BOOLEAN NOT NULL DEFAULT false"),
    ("old_tax_system_notes", "TEXT"),
    ("new_tax_system_notes", "TEXT"),
]

STOCK_ENTRY_COLUMNS = [
    ("confirmed_at", "TIMESTAMP WITH TIME ZONE"),
]

STOCK_ENTRY_ITEM_COLUMNS = [
    ("invoice_quantity", "NUMERIC(12, 3)"),
    ("invoice_unit", "VARCHAR(20)"),
    ("package_conversion_factor", "NUMERIC(12, 4)"),
    ("received_quantity", "NUMERIC(12, 3)"),
    ("batch_number", "VARCHAR(80)"),
    ("expiration_date", "DATE"),
    ("check_status", "VARCHAR(30) NOT NULL DEFAULT 'accepted'"),
    ("check_notes", "TEXT"),
    ("origin", "VARCHAR(2)"),
    ("cst", "VARCHAR(10)"),
    ("csosn", "VARCHAR(10)"),
    ("icms_rate", "NUMERIC(7, 4)"),
    ("pis_rate", "NUMERIC(7, 4)"),
    ("cofins_rate", "NUMERIC(7, 4)"),
    ("ipi_rate", "NUMERIC(7, 4)"),
    ("ibs_cbs_cst", "VARCHAR(10)"),
    ("ibs_cbs_classification", "VARCHAR(20)"),
    ("cbs_rate", "NUMERIC(7, 4)"),
    ("ibs_state_rate", "NUMERIC(7, 4)"),
    ("ibs_city_rate", "NUMERIC(7, 4)"),
    ("selective_tax_cst", "VARCHAR(10)"),
    ("selective_tax_classification", "VARCHAR(20)"),
    ("selective_tax_rate", "NUMERIC(7, 4)"),
]

CASH_CLOSING_COLUMNS = [
    ("cash_session_id", "INTEGER"),
    ("cash_register_number", "VARCHAR(10)"),
    ("authorized_by_operator_id", "INTEGER"),
    ("authorized_by_operator_name", "VARCHAR(150)"),
    ("business_date", "DATE"),
    ("crossed_business_day", "BOOLEAN NOT NULL DEFAULT false"),
    ("business_day_cutoff_minutes", "INTEGER NOT NULL DEFAULT 180"),
]

CASH_CLOSING_MOVEMENT_COLUMNS = [
    ("authorized_by_operator_id", "INTEGER"),
    ("authorized_by_operator_name", "VARCHAR(150)"),
]

SALE_COLUMNS = [
    ("cash_session_id", "INTEGER"),
    ("consumer_cpf", "VARCHAR(14)"),
    ("offline_client_id", "VARCHAR(80)"),
    ("cash_register_number", "VARCHAR(10)"),
]

PDV_TERMINAL_COLUMNS = [
    ("activation_code_hash", "VARCHAR(180)"),
    ("activation_code_expires_at", "TIMESTAMP WITH TIME ZONE"),
    ("activated_at", "TIMESTAMP WITH TIME ZONE"),
    ("activation_status", "VARCHAR(30) NOT NULL DEFAULT 'active'"),
    ("machine_name", "VARCHAR(120)"),
    ("windows_user", "VARCHAR(120)"),
    ("windows_version", "VARCHAR(120)"),
    ("device_fingerprint", "VARCHAR(180)"),
    ("current_status", "VARCHAR(30)"),
    ("current_operator_name", "VARCHAR(150)"),
    ("cash_opened_at", "TIMESTAMP WITH TIME ZONE"),
    ("current_session_total_amount", "NUMERIC(12, 2)"),
]

USER_COLUMNS = [
    ("seller_code", "VARCHAR(40)"),
    ("technician_code", "VARCHAR(40)"),
    ("must_change_password", "BOOLEAN NOT NULL DEFAULT false"),
    ("password_changed_at", "TIMESTAMP WITH TIME ZONE"),
]

ROLE_COLUMNS = [
    ("is_seller_profile", "BOOLEAN NOT NULL DEFAULT false"),
    ("is_technician_profile", "BOOLEAN NOT NULL DEFAULT false"),
]

FISCAL_SETTING_COLUMNS = [
    ("certificate_encrypted_blob", "BYTEA"),
    ("certificate_password_encrypted", "TEXT"),
    ("certificate_file_sha256", "VARCHAR(64)"),
    ("pdv_nfce_enabled", "BOOLEAN NOT NULL DEFAULT false"),
    ("address_line", "VARCHAR(180)"),
    ("address_number", "VARCHAR(20)"),
    ("neighborhood", "VARCHAR(120)"),
    ("city", "VARCHAR(120)"),
    ("zip_code", "VARCHAR(20)"),
    ("logo_url", "TEXT"),
    ("nfce_last_authorized_number", "INTEGER"),
    ("nfe_last_authorized_number", "INTEGER"),
]

FISCAL_DOCUMENT_COLUMNS = [
    ("cancellation_reason", "VARCHAR(255)"),
    ("cancellation_protocol", "VARCHAR(80)"),
    ("cancellation_status_code", "VARCHAR(20)"),
    ("cancellation_message", "TEXT"),
    ("cancellation_xml", "TEXT"),
    ("operation_nature", "VARCHAR(120)"),
    ("payment_condition", "VARCHAR(20)"),
    ("fiscal_notes", "TEXT"),
    ("finality", "VARCHAR(1) NOT NULL DEFAULT '1'"),
    ("freight_mode", "VARCHAR(2)"),
    ("freight_amount", "NUMERIC(12, 2) NOT NULL DEFAULT 0"),
    ("insurance_amount", "NUMERIC(12, 2) NOT NULL DEFAULT 0"),
    ("other_expenses_amount", "NUMERIC(12, 2) NOT NULL DEFAULT 0"),
    ("carrier_name", "VARCHAR(180)"),
    ("carrier_document", "VARCHAR(20)"),
    ("carrier_state_registration", "VARCHAR(20)"),
    ("carrier_address", "VARCHAR(180)"),
    ("carrier_city", "VARCHAR(120)"),
    ("carrier_uf", "VARCHAR(2)"),
    ("volume_quantity", "NUMERIC(12, 3)"),
    ("volume_species", "VARCHAR(60)"),
    ("volume_brand", "VARCHAR(60)"),
    ("volume_numbering", "VARCHAR(60)"),
    ("net_weight", "NUMERIC(12, 3)"),
    ("gross_weight", "NUMERIC(12, 3)"),
]

FISCAL_DOCUMENT_ITEM_COLUMNS = [
    ("ncm", "VARCHAR(20)"), ("cest", "VARCHAR(20)"), ("cfop", "VARCHAR(10)"),
    ("origin", "VARCHAR(2)"), ("cst", "VARCHAR(10)"), ("csosn", "VARCHAR(10)"),
    ("pis_cst", "VARCHAR(10)"), ("cofins_cst", "VARCHAR(10)"), ("cbenef", "VARCHAR(20)"),
]

PRODUCTION_ORDER_COLUMNS = [
    ("completed_by_user_id", "INTEGER"),
    ("canceled_by_user_id", "INTEGER"),
    ("produced_quantity", "NUMERIC(12, 3) NOT NULL DEFAULT 0"),
    ("estimated_unit_cost", "NUMERIC(12, 2)"),
    ("estimated_total_cost", "NUMERIC(12, 2)"),
    ("due_date", "DATE"),
    ("cancellation_reason", "TEXT"),
    ("started_at", "TIMESTAMP WITH TIME ZONE"),
    ("completed_at", "TIMESTAMP WITH TIME ZONE"),
    ("canceled_at", "TIMESTAMP WITH TIME ZONE"),
]


def column_exists(table_name: str, column_name: str, bind_engine=engine) -> bool:
    with bind_engine.connect() as connection:
        return column_exists_in_connection(connection, table_name, column_name)


def column_exists_in_connection(connection, table_name: str, column_name: str) -> bool:
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


def add_client_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in CLIENT_COLUMNS:
            if not column_exists_in_connection(connection, "clients", column_name):
                connection.execute(
                    text(f"ALTER TABLE clients ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text("ALTER TABLE clients ALTER COLUMN person_type SET DEFAULT 'PF'")
        )

        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_clients_document_number
                ON clients(document_number)
                """
            )
        )


def add_equipment_columns() -> None:
    with engine.begin() as connection:
        for column_name, column_type in EQUIPMENT_COLUMNS:
            if not column_exists("equipments", column_name):
                connection.execute(
                    text(f"ALTER TABLE equipments ADD COLUMN {column_name} {column_type}")
                )

        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_equipments_asset_tag
                ON equipments(asset_tag)
                """
            )
        )


def add_alert_columns() -> None:
    with engine.begin() as connection:
        for column_name, column_type in ALERT_COLUMNS:
            if not column_exists("alerts", column_name):
                connection.execute(
                    text(f"ALTER TABLE alerts ADD COLUMN {column_name} {column_type}")
                )


def add_equipment_current_status_columns() -> None:
    with engine.begin() as connection:
        for column_name, column_type in EQUIPMENT_CURRENT_STATUS_COLUMNS:
            if not column_exists("equipment_current_status", column_name):
                connection.execute(
                    text(
                        "ALTER TABLE equipment_current_status "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )


def add_service_order_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in SERVICE_ORDER_COLUMNS:
            if not column_exists_in_connection(connection, "service_orders", column_name):
                connection.execute(
                    text(f"ALTER TABLE service_orders ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                UPDATE service_orders
                SET number = 'M' || id
                WHERE number IS NULL OR trim(number) = ''
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS service_order_events (
                    id SERIAL PRIMARY KEY,
                    service_order_id INTEGER NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
                    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    event_type VARCHAR(40) NOT NULL,
                    status_from VARCHAR(30),
                    status_to VARCHAR(30),
                    assigned_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    notes TEXT,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_service_order_events_order
                ON service_order_events(service_order_id)
                """
            )
        )


def add_product_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        if (
            column_exists_in_connection(connection, "products", "cost_price")
            and not column_exists_in_connection(connection, "products", "purchase_total_cost")
        ):
            connection.execute(text("ALTER TABLE products RENAME COLUMN cost_price TO purchase_total_cost"))
        if (
            column_exists_in_connection(connection, "products", "cost_quantity")
            and not column_exists_in_connection(connection, "products", "purchase_quantity")
        ):
            connection.execute(text("ALTER TABLE products RENAME COLUMN cost_quantity TO purchase_quantity"))
        for column_name, column_type in PRODUCT_COLUMNS:
            if not column_exists_in_connection(connection, "products", column_name):
                connection.execute(
                    text(f"ALTER TABLE products ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                ALTER TABLE products
                    ALTER COLUMN sale_price TYPE NUMERIC(12, 4) USING sale_price::NUMERIC(12, 4),
                    ALTER COLUMN offer_price TYPE NUMERIC(12, 4) USING offer_price::NUMERIC(12, 4)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_products_barcode
                ON products(barcode)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_products_purchase_package_barcode
                ON products(purchase_package_barcode)
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE products
                SET purchase_quantity = stock_quantity
                WHERE purchase_quantity IS NULL
                  AND purchase_total_cost IS NOT NULL
                  AND stock_quantity > 0
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE products
                SET average_cost = CASE
                    WHEN average_cost IS NOT NULL THEN average_cost
                    WHEN purchase_total_cost IS NOT NULL AND purchase_quantity IS NOT NULL AND purchase_quantity > 0
                        THEN purchase_total_cost / purchase_quantity
                    WHEN purchase_total_cost IS NOT NULL AND stock_quantity > 0
                        THEN purchase_total_cost / stock_quantity
                    ELSE 0
                END
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE products
                SET stock_value = COALESCE(stock_quantity, 0) * COALESCE(average_cost, 0)
                WHERE stock_value IS NULL OR stock_value = 0
                """
            )
        )


def add_marketplace_tables(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS marketplace_connections (
                    id SERIAL PRIMARY KEY,
                    provider VARCHAR(40) NOT NULL DEFAULT 'mercado_livre',
                    account_id VARCHAR(80),
                    nickname VARCHAR(160),
                    site_id VARCHAR(10),
                    status VARCHAR(30) NOT NULL DEFAULT 'pending',
                    access_token TEXT,
                    refresh_token TEXT,
                    token_type VARCHAR(40),
                    expires_at TIMESTAMP WITH TIME ZONE,
                    scopes JSON NOT NULL DEFAULT '[]',
                    raw_account JSON NOT NULL DEFAULT '{}',
                    last_sync_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_marketplace_connection_account
                ON marketplace_connections(provider, account_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS product_marketplace_listings (
                    id SERIAL PRIMARY KEY,
                    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                    provider VARCHAR(40) NOT NULL DEFAULT 'mercado_livre',
                    listing_id VARCHAR(80),
                    enabled BOOLEAN NOT NULL DEFAULT false,
                    sync_stock BOOLEAN NOT NULL DEFAULT true,
                    sync_price BOOLEAN NOT NULL DEFAULT true,
                    status VARCHAR(30) NOT NULL DEFAULT 'draft',
                    title VARCHAR(180),
                    permalink TEXT,
                    category_id VARCHAR(60),
                    listing_type_id VARCHAR(60),
                    condition VARCHAR(20) NOT NULL DEFAULT 'new',
                    last_error TEXT,
                    last_synced_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_product_marketplace_provider
                ON product_marketplace_listings(product_id, provider)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_product_marketplace_listing_id
                ON product_marketplace_listings(listing_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS marketplace_oauth_states (
                    id SERIAL PRIMARY KEY,
                    provider VARCHAR(40) NOT NULL DEFAULT 'mercado_livre',
                    state VARCHAR(120) NOT NULL UNIQUE,
                    tenant_code VARCHAR(120) NOT NULL,
                    created_by_user_id INTEGER,
                    used_at TIMESTAMP WITH TIME ZONE,
                    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_oauth_state
                ON marketplace_oauth_states(state)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS marketplace_notifications (
                    id SERIAL PRIMARY KEY,
                    provider VARCHAR(40) NOT NULL DEFAULT 'mercado_livre',
                    topic VARCHAR(80),
                    resource TEXT,
                    external_user_id VARCHAR(80),
                    application_id VARCHAR(80),
                    attempts INTEGER,
                    sent_at TIMESTAMP WITH TIME ZONE,
                    status VARCHAR(30) NOT NULL DEFAULT 'received',
                    payload JSON NOT NULL DEFAULT '{}',
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_topic
                ON marketplace_notifications(topic)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_external_user
                ON marketplace_notifications(external_user_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS marketplace_sync_jobs (
                    id SERIAL PRIMARY KEY,
                    provider VARCHAR(40) NOT NULL DEFAULT 'mercado_livre',
                    job_type VARCHAR(60) NOT NULL,
                    status VARCHAR(30) NOT NULL DEFAULT 'pending',
                    product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
                    listing_id VARCHAR(80),
                    resource TEXT,
                    payload JSON NOT NULL DEFAULT '{}',
                    attempts INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                    processed_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
                )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_sync_jobs_status
                ON marketplace_sync_jobs(status)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_sync_jobs_job_type
                ON marketplace_sync_jobs(job_type)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_sync_jobs_product_id
                ON marketplace_sync_jobs(product_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_sync_jobs_listing_id
                ON marketplace_sync_jobs(listing_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_marketplace_sync_jobs_scheduled_at
                ON marketplace_sync_jobs(scheduled_at)
                """
            )
        )


def add_stock_entry_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in STOCK_ENTRY_COLUMNS:
            if not column_exists_in_connection(connection, "stock_entries", column_name):
                connection.execute(
                    text(f"ALTER TABLE stock_entries ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in STOCK_ENTRY_ITEM_COLUMNS:
            if not column_exists_in_connection(connection, "stock_entry_items", column_name):
                connection.execute(
                    text(f"ALTER TABLE stock_entry_items ADD COLUMN {column_name} {column_type}")
                )


def add_cash_closing_audit_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in CASH_CLOSING_COLUMNS:
            if not column_exists_in_connection(connection, "cash_closings", column_name):
                connection.execute(
                    text(f"ALTER TABLE cash_closings ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_cash_closings_cash_session_id
                ON cash_closings(cash_session_id)
                """
            )
        )
        for column_name, column_type in CASH_CLOSING_MOVEMENT_COLUMNS:
            if not column_exists_in_connection(connection, "cash_closing_movements", column_name):
                connection.execute(
                    text(f"ALTER TABLE cash_closing_movements ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                ALTER TABLE stock_entry_items
                ALTER COLUMN product_id DROP NOT NULL
                """
            )
        )


def add_sale_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in SALE_COLUMNS:
            if not column_exists_in_connection(connection, "sales", column_name):
                connection.execute(text(f"ALTER TABLE sales ADD COLUMN {column_name} {column_type}"))
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_sales_cash_session_id
                ON sales(cash_session_id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_sales_consumer_cpf
                ON sales(consumer_cpf)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_offline_client_id
                ON sales(offline_client_id)
                WHERE offline_client_id IS NOT NULL AND offline_client_id <> ''
                """
            )
        )
        connection.execute(
            text(
                """
                ALTER TABLE sale_items
                    ALTER COLUMN unit_price TYPE NUMERIC(12, 4) USING unit_price::NUMERIC(12, 4)
                """
            )
        )


def add_pdv_terminal_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        connection.execute(
            text(
                """
                ALTER TABLE pdv_terminals
                    ALTER COLUMN terminal_key TYPE VARCHAR(180)
                    USING terminal_key::VARCHAR(180)
                """
            )
        )
        for column_name, column_type in PDV_TERMINAL_COLUMNS:
            if not column_exists_in_connection(connection, "pdv_terminals", column_name):
                connection.execute(
                    text(f"ALTER TABLE pdv_terminals ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_pdv_terminal_cash_register_number
                ON pdv_terminals(cash_register_number)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_pdv_terminal_terminal_key
                ON pdv_terminals(terminal_key)
                """
            )
        )


def add_user_seller_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in ROLE_COLUMNS:
            if not column_exists_in_connection(connection, "roles", column_name):
                connection.execute(text(f"ALTER TABLE roles ADD COLUMN {column_name} {column_type}"))
        for column_name, column_type in USER_COLUMNS:
            if not column_exists_in_connection(connection, "users", column_name):
                connection.execute(text(f"ALTER TABLE users ADD COLUMN {column_name} {column_type}"))
        connection.execute(
            text(
                """
                UPDATE users
                SET seller_code = 'V' || LPAD(id::text, 3, '0')
                WHERE seller_code IS NULL OR seller_code = ''
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_users_seller_code
                ON users(seller_code)
                WHERE seller_code IS NOT NULL
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_users_technician_code
                ON users(technician_code)
                WHERE technician_code IS NOT NULL
                """
            )
        )


def normalize_sale_sources(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE sales
                SET source = 'pdv'
                WHERE source = 'teste'
                """
            )
        )


def add_fiscal_setting_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in FISCAL_SETTING_COLUMNS:
            if not column_exists_in_connection(connection, "company_fiscal_settings", column_name):
                connection.execute(
                    text(f"ALTER TABLE company_fiscal_settings ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in FISCAL_DOCUMENT_COLUMNS:
            if not column_exists_in_connection(connection, "fiscal_documents", column_name):
                connection.execute(
                    text(f"ALTER TABLE fiscal_documents ADD COLUMN {column_name} {column_type}")
                )
        for column_name, column_type in FISCAL_DOCUMENT_ITEM_COLUMNS:
            if not column_exists_in_connection(connection, "fiscal_document_items", column_name):
                connection.execute(
                    text(f"ALTER TABLE fiscal_document_items ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                UPDATE company_fiscal_settings
                SET pdv_nfce_enabled = false
                WHERE pdv_nfce_enabled IS NULL
                """
            )
        )
        connection.execute(
            text(
                """
                ALTER TABLE company_fiscal_settings
                ALTER COLUMN pdv_nfce_enabled SET DEFAULT false,
                ALTER COLUMN pdv_nfce_enabled SET NOT NULL
                """
            )
        )
        connection.execute(
            text(
                """
                ALTER TABLE stock_entries
                ALTER COLUMN confirmed_at DROP NOT NULL
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE stock_entry_items
                SET received_quantity = quantity
                WHERE received_quantity IS NULL
                """
            )
        )
        duplicate_number = connection.execute(
            text(
                """
                SELECT 1
                FROM fiscal_documents
                WHERE number IS NOT NULL
                GROUP BY environment, document_type, series, number
                HAVING COUNT(*) > 1
                LIMIT 1
                """
            )
        ).first()
        if duplicate_number is None:
            connection.execute(
                text(
                    """
                    CREATE UNIQUE INDEX IF NOT EXISTS uq_fiscal_document_number
                    ON fiscal_documents (environment, document_type, series, number)
                    WHERE number IS NOT NULL
                    """
                )
            )


def add_production_order_columns(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        for column_name, column_type in PRODUCTION_ORDER_COLUMNS:
            if not column_exists_in_connection(connection, "production_orders", column_name):
                connection.execute(
                    text(f"ALTER TABLE production_orders ADD COLUMN {column_name} {column_type}")
                )
        connection.execute(
            text(
                """
                UPDATE production_orders
                SET produced_quantity = quantity
                WHERE status = 'concluida'
                  AND COALESCE(produced_quantity, 0) = 0
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE production_orders
                SET status = 'planejada'
                WHERE status IS NULL OR trim(status) = ''
                """
            )
        )


def backfill_product_batches(bind_engine=engine) -> None:
    with bind_engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO product_batches (
                    product_id,
                    batch_number,
                    expiration_date,
                    quantity,
                    unit,
                    source_type,
                    source_id,
                    source_number,
                    supplier_name,
                    invoice_number,
                    invoice_series,
                    notes,
                    active
                )
                SELECT
                    item.product_id,
                    NULLIF(trim(item.batch_number), ''),
                    item.expiration_date,
                    SUM(COALESCE(item.received_quantity, item.quantity)),
                    product.unit,
                    'stock_entry',
                    MIN(entry.id),
                    MIN(entry.invoice_number),
                    MIN(entry.supplier_name),
                    MIN(entry.invoice_number),
                    MIN(entry.invoice_series),
                    'Lote reconstruido pela migracao a partir de entrada de estoque.',
                    true
                FROM stock_entry_items item
                JOIN stock_entries entry ON entry.id = item.stock_entry_id
                JOIN products product ON product.id = item.product_id
                WHERE item.product_id IS NOT NULL
                  AND COALESCE(item.check_status, 'accepted') = 'accepted'
                  AND COALESCE(item.received_quantity, item.quantity) > 0
                  AND (
                    product.tracks_batch = true
                    OR item.batch_number IS NOT NULL
                    OR item.expiration_date IS NOT NULL
                  )
                  AND NOT EXISTS (
                    SELECT 1
                    FROM product_batches existing
                    WHERE existing.product_id = item.product_id
                      AND COALESCE(existing.batch_number, '') = COALESCE(NULLIF(trim(item.batch_number), ''), '')
                      AND COALESCE(existing.expiration_date, DATE '1900-01-01') =
                          COALESCE(item.expiration_date, DATE '1900-01-01')
                  )
                GROUP BY
                    item.product_id,
                    NULLIF(trim(item.batch_number), ''),
                    item.expiration_date,
                    product.unit
                """
            )
        )
        connection.execute(
            text(
                """
                INSERT INTO product_batches (
                    product_id,
                    batch_number,
                    expiration_date,
                    quantity,
                    unit,
                    source_type,
                    source_id,
                    source_number,
                    notes,
                    active
                )
                SELECT
                    product.id,
                    NULLIF(trim(product.initial_batch_number), ''),
                    product.initial_expiration_date,
                    product.stock_quantity,
                    product.unit,
                    'product_initial',
                    product.id,
                    product.internal_code,
                    'Saldo inicial reconstruido pela migracao do cadastro do produto.',
                    true
                FROM products product
                WHERE product.stock_quantity > 0
                  AND (
                    product.tracks_batch = true
                    OR product.initial_batch_number IS NOT NULL
                    OR product.initial_expiration_date IS NOT NULL
                  )
                  AND NOT EXISTS (
                    SELECT 1
                    FROM product_batches existing
                    WHERE existing.product_id = product.id
                  )
                """
            )
        )


def _public_upload_path(url: str | None) -> str | None:
    if not url:
        return None
    parsed = urlparse(str(url))
    public_path = unquote(parsed.path or str(url))
    if public_path.startswith("/public/"):
        return public_path
    return None


def cleanup_orphan_product_images(company_code: str, bind_engine=engine) -> None:
    scope = safe_scope_name(f"tenant-products-{company_code}")
    target_dir = (UPLOAD_ROOT / scope).resolve()
    if not target_dir.is_dir():
        return
    with bind_engine.connect() as connection:
        if (
            connection.execute(text("SELECT to_regclass('public.products')")).scalar()
            is None
        ):
            return
        rows = connection.execute(
            text(
                """
                SELECT image_url
                FROM products
                WHERE image_url IS NOT NULL
                  AND trim(image_url) <> ''
                """
            )
        ).scalars()
        used_paths = {
            path
            for path in (_public_upload_path(row) for row in rows)
            if path is not None
        }
    for file_path in target_dir.iterdir():
        if not file_path.is_file():
            continue
        resolved = file_path.resolve()
        if target_dir not in resolved.parents:
            continue
        public_path = f"/public/{scope}/{file_path.name}"
        if public_path in used_paths:
            continue
        try:
            resolved.unlink()
        except OSError:
            continue


def migrate_registered_tenants() -> None:
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    with MasterSessionLocal() as master_db:
        companies = list(master_db.query(Company).all())

    for registered_company in companies:
        tenant_engine = create_engine(registered_company.database_url, pool_pre_ping=True)
        try:
            Base.metadata.create_all(bind=tenant_engine)
            add_client_columns(tenant_engine)
            add_product_columns(tenant_engine)
            add_stock_entry_columns(tenant_engine)
            add_cash_closing_audit_columns(tenant_engine)
            add_sale_columns(tenant_engine)
            add_pdv_terminal_columns(tenant_engine)
            normalize_sale_sources(tenant_engine)
            add_user_seller_columns(tenant_engine)
            add_service_order_columns(tenant_engine)
            add_fiscal_setting_columns(tenant_engine)
            with tenant_engine.begin() as connection:
                connection.execute(
                    text(
                        """
                        UPDATE company_fiscal_settings
                        SET
                            cnpj = COALESCE(NULLIF(cnpj, ''), :cnpj),
                            state_registration = COALESCE(NULLIF(state_registration, ''), :state_registration),
                            address_line = COALESCE(NULLIF(address_line, ''), :address_line),
                            address_number = COALESCE(NULLIF(address_number, ''), :address_number),
                            neighborhood = COALESCE(NULLIF(neighborhood, ''), :neighborhood),
                            city = COALESCE(NULLIF(city, ''), :city),
                            city_code = COALESCE(NULLIF(city_code, ''), :city_code),
                            uf = COALESCE(NULLIF(uf, ''), :state),
                            zip_code = COALESCE(NULLIF(zip_code, ''), :zip_code)
                        """
                    ),
                    {
                        "cnpj": registered_company.document_number,
                        "state_registration": registered_company.state_registration,
                        "address_line": registered_company.address_line,
                        "address_number": registered_company.address_number,
                        "neighborhood": registered_company.neighborhood,
                        "city": registered_company.city,
                        "city_code": registered_company.city_code,
                        "state": registered_company.state,
                        "zip_code": registered_company.zip_code,
                    },
                )
            add_production_order_columns(tenant_engine)
            add_marketplace_tables(tenant_engine)
            backfill_product_batches(tenant_engine)
            TenantSessionLocal = sessionmaker(
                bind=tenant_engine,
                autocommit=False,
                autoflush=False,
            )
            with TenantSessionLocal() as tenant_db:
                seed_default_access_control(tenant_db)
            cleanup_orphan_product_images(registered_company.code, tenant_engine)
        finally:
            tenant_engine.dispose()


def sync_master_user_index_from_tenants() -> None:
    from sqlalchemy import create_engine, text

    ignored_emails = {"_pdv_terminal@lyncar.local"}

    with MasterSessionLocal() as master_db:
        companies = list(master_db.query(Company).all())

    for registered_company in companies:
        tenant_engine = create_engine(registered_company.database_url, pool_pre_ping=True)
        try:
            with tenant_engine.connect() as connection:
                if (
                    connection.execute(text("SELECT to_regclass('public.users')")).scalar()
                    is None
                ):
                    continue
                users = connection.execute(
                    text(
                        """
                        SELECT id, name, lower(trim(email)) AS email, role, active
                        FROM users
                        WHERE email IS NOT NULL AND trim(email) <> ''
                        ORDER BY id
                        """
                    )
                ).mappings()
                for existing_user in users:
                    if existing_user["email"] in ignored_emails:
                        continue
                    upsert_user_index(
                        company_code=registered_company.code,
                        company_name=registered_company.name,
                        user_id=existing_user["id"],
                        name=existing_user["name"],
                        email=existing_user["email"],
                        role=existing_user["role"],
                        active=existing_user["active"],
                    )
        finally:
            tenant_engine.dispose()


def main() -> None:
    migrate_master()
    Base.metadata.create_all(bind=engine)
    add_client_columns()
    add_equipment_columns()
    add_alert_columns()
    add_equipment_current_status_columns()
    add_service_order_columns()
    add_product_columns()
    add_marketplace_tables()
    add_stock_entry_columns()
    add_cash_closing_audit_columns()
    add_sale_columns()
    add_pdv_terminal_columns()
    normalize_sale_sources()
    add_user_seller_columns()
    add_fiscal_setting_columns()
    add_production_order_columns()
    backfill_product_batches()
    cleanup_orphan_product_images("tenant")
    from app.core.database import SessionLocal

    with SessionLocal() as db:
        seed_default_access_control(db)
    migrate_registered_tenants()
    sync_master_user_index_from_tenants()
    print("Migracao local aplicada com sucesso.")


if __name__ == "__main__":
    main()

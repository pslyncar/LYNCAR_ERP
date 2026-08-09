import re

from sqlalchemy import create_engine, select, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import sessionmaker

from app.core.config import get_settings
from app.core.database import Base
from app.core.security import hash_password
from app.models import access_control, cash_closing, client, equipment, equipment_status, fiscal, fiscal_assistant, monitoring, payable, pdv_cash_session, pdv_operator, pdv_terminal, product, product_batch, product_composition, production_order, receivable, sale, service_contract, service_order, stock_entry, stock_movement, supplier, ticket, user, xml_inbox  # noqa: F401
from app.models.user import User
from app.services.access_control import seed_default_access_control
from app.services.tenancy import normalize_company_code


def database_name_for_company(company_code: str) -> str:
    normalized = normalize_company_code(company_code)
    cleaned = re.sub(r"[^a-z0-9_]+", "_", normalized).strip("_")
    return f"papezzosync_{cleaned}"


def database_url_for_company(base_database_url: str, company_code: str) -> str:
    url = make_url(base_database_url)
    return url.set(database=database_name_for_company(company_code)).render_as_string(
        hide_password=False
    )


def ensure_database_exists(database_url: str) -> None:
    url = make_url(database_url)
    database_name = url.database
    if not database_name:
        raise ValueError("URL do banco sem nome de database.")

    settings = get_settings()
    maintenance_url = make_url(settings.database_url)
    if maintenance_url.database == database_name:
        return
    maintenance_engine = create_engine(
        maintenance_url,
        isolation_level="AUTOCOMMIT",
        pool_pre_ping=True,
    )
    quoted_database_name = database_name.replace('"', '""')
    try:
        with maintenance_engine.connect() as connection:
            exists = connection.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :database_name"),
                {"database_name": database_name},
            ).first()
            if exists is None:
                connection.execute(text(f'CREATE DATABASE "{quoted_database_name}"'))
    finally:
        maintenance_engine.dispose()


def migrate_tenant_database(database_url: str) -> Engine:
    engine = create_engine(database_url, pool_pre_ping=True)
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    with SessionLocal() as db:
        seed_default_access_control(db)
    return engine


def ensure_initial_admin(
    database_url: str,
    *,
    name: str,
    email: str,
    password: str,
) -> None:
    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    with SessionLocal() as db:
        existing_user = db.scalar(select(User).where(User.email == email.lower()))
        if existing_user is not None:
            return
        db.add(
            User(
                name=name,
                email=email.lower(),
                password_hash=hash_password(password),
                must_change_password=True,
                role="admin",
                active=True,
            )
        )
        db.commit()


def provision_tenant_database(
    database_url: str,
    *,
    admin_name: str,
    admin_email: str,
    admin_password: str,
) -> None:
    ensure_database_exists(database_url)
    engine = migrate_tenant_database(database_url)
    engine.dispose()
    ensure_initial_admin(
        database_url,
        name=admin_name,
        email=admin_email,
        password=admin_password,
    )

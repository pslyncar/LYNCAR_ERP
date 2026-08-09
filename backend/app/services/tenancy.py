from functools import lru_cache

from sqlalchemy import select
from sqlalchemy.engine import Engine
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings
from app.core.security import hash_password
from app.core.master_database import MasterSessionLocal, master_engine
from app.models.company import Company
from app.models import master_permission as _master_permission  # noqa: F401
from app.models import master_support as _master_support  # noqa: F401
from app.models.master_user import MasterUser
from app.models.master_user_index import MasterUserIndex
from app.services.company_modules import ALL_MODULES, filter_modules_by_plan


def normalize_company_code(value: str) -> str:
    return value.strip().lower().replace(" ", "-")


def seed_master_identity() -> None:
    from app.core.master_database import MasterBase

    settings = get_settings()
    MasterBase.metadata.create_all(bind=master_engine)
    with MasterSessionLocal() as db:
        user = db.scalar(
            select(MasterUser).where(
                MasterUser.email == settings.master_admin_email.lower()
            )
        )
        if user is None:
            db.add(
                MasterUser(
                    name="Superadmin PapezzoSync",
                    email=settings.master_admin_email.lower(),
                    password_hash=hash_password(settings.master_admin_password),
                    active=True,
                )
            )
            db.commit()


def seed_default_company() -> None:
    seed_master_identity()


def get_company_by_code(company_code: str) -> Company | None:
    normalized = normalize_company_code(company_code)
    with MasterSessionLocal() as db:
        return db.scalar(select(Company).where(Company.code == normalized))


def require_active_company(company_code: str) -> Company:
    company = get_company_by_code(company_code)
    if company is None or not company.active or company.status != "active":
        raise LookupError("Empresa nao encontrada ou inativa.")
    return company


def get_enabled_modules_for_company(company_code: str) -> list[str]:
    company = get_company_by_code(company_code)
    if company is None:
        return ALL_MODULES
    return filter_modules_by_plan(company.enabled_modules or ALL_MODULES, company.plan)


@lru_cache(maxsize=128)
def _tenant_engine(database_url: str) -> Engine:
    return create_engine(database_url, pool_pre_ping=True)


@lru_cache(maxsize=128)
def _tenant_sessionmaker(database_url: str) -> sessionmaker[Session]:
    return sessionmaker(
        bind=_tenant_engine(database_url),
        autocommit=False,
        autoflush=False,
    )


def session_for_company(company_code: str) -> Session:
    company = require_active_company(company_code)
    return _tenant_sessionmaker(company.database_url)()

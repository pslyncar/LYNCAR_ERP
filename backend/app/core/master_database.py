from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import get_settings

settings = get_settings()

master_engine = create_engine(settings.master_database_url, pool_pre_ping=True)
MasterSessionLocal = sessionmaker(
    bind=master_engine,
    autocommit=False,
    autoflush=False,
)


class MasterBase(DeclarativeBase):
    pass

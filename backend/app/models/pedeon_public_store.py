from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class PedeOnPublicStore(MasterBase):
    """Índice global que impede duas empresas de usarem o mesmo endereço."""

    __tablename__ = "pedeon_public_stores"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_code: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )
    public_slug: Mapped[str] = mapped_column(
        String(80), nullable=False, unique=True, index=True
    )
    tenant_store_id: Mapped[int] = mapped_column(Integer, nullable=False)
    display_name: Mapped[str] = mapped_column(String(180), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

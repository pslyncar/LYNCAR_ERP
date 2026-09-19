from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, JSON, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterPedeOnCustomer(MasterBase):
    """Identidade global do consumidor; pedidos permanecem por empresa."""

    __tablename__ = "master_pedeon_customers"
    __table_args__ = (UniqueConstraint("email", name="uq_master_pedeon_customer_email"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(180), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(180), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(40))
    document_number: Mapped[str | None] = mapped_column(String(30))
    delivery_address: Mapped[dict | None] = mapped_column(JSON)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, index=True)
    blocked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MasterPedeOnCustomerIdentity(MasterBase):
    """Identidade imutável retornada por Google, Facebook ou Apple."""

    __tablename__ = "master_pedeon_customer_identities"
    __table_args__ = (
        UniqueConstraint("provider", "provider_subject", name="uq_master_pedeon_identity"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    customer_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    provider_subject: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class MasterPedeOnCustomerStoreLink(MasterBase):
    """Lojas em que a conta global já foi usada, para suporte e auditoria."""

    __tablename__ = "master_pedeon_customer_store_links"
    __table_args__ = (
        UniqueConstraint(
            "customer_id", "company_code", "store_slug", name="uq_master_pedeon_store_link"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    customer_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    company_code: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    store_slug: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    local_customer_id: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, JSON, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PedeOnCustomer(Base):
    """Conta do consumidor do cardápio público, isolada dos usuários internos."""

    __tablename__ = "pedeon_customers"
    __table_args__ = (
        UniqueConstraint("store_id", "email", name="uq_pedeon_customer_store_email"),
        UniqueConstraint(
            "store_id", "provider", "provider_subject",
            name="uq_pedeon_customer_store_provider_subject",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    store_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    global_customer_id: Mapped[int | None] = mapped_column(Integer, index=True)
    name: Mapped[str] = mapped_column(String(180), nullable=False)
    email: Mapped[str] = mapped_column(String(180), nullable=False, index=True)
    phone: Mapped[str | None] = mapped_column(String(40))
    document_number: Mapped[str | None] = mapped_column(String(30))
    delivery_address: Mapped[dict | None] = mapped_column(JSON)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    provider: Mapped[str] = mapped_column(String(20), nullable=False, default="pedeon")
    provider_subject: Mapped[str | None] = mapped_column(String(255))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

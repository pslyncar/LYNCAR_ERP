from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PedeOnPaymentConfiguration(Base):
    __tablename__ = "pedeon_payment_configurations"
    __table_args__ = (
        UniqueConstraint("store_id", "method", name="uq_pedeon_payment_config_method"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    method: Mapped[str] = mapped_column(String(40), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    display_name: Mapped[str | None] = mapped_column(String(120))
    public_configuration: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    encrypted_credentials: Mapped[str | None] = mapped_column(Text)
    auto_accept_after_confirmation: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnPaymentTransaction(Base):
    __tablename__ = "pedeon_payment_transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_orders.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    idempotency_key: Mapped[str] = mapped_column(String(120), nullable=False, unique=True)
    method: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    provider: Mapped[str | None] = mapped_column(String(40), index=True)
    status: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    provider_order_id: Mapped[str | None] = mapped_column(String(120), index=True)
    provider_transaction_id: Mapped[str | None] = mapped_column(
        String(120), unique=True, index=True
    )
    provider_invoice_slug: Mapped[str | None] = mapped_column(String(160), index=True)
    checkout_url: Mapped[str | None] = mapped_column(Text)
    receipt_url: Mapped[str | None] = mapped_column(Text)
    manual_reference: Mapped[str | None] = mapped_column(String(180))
    metadata_payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    confirmed_by_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refunded_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


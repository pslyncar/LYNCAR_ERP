from datetime import datetime
from decimal import Decimal
from secrets import token_urlsafe
from uuid import uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PedeOnOrder(Base):
    __tablename__ = "pedeon_orders"
    __table_args__ = (
        CheckConstraint("version > 0", name="ck_pedeon_order_version_positive"),
        CheckConstraint("total_amount >= 0", name="ck_pedeon_order_total_nonnegative"),
        UniqueConstraint(
            "store_id",
            "source_channel",
            "external_order_id",
            name="uq_pedeon_order_source_external",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    public_id: Mapped[str] = mapped_column(
        String(36), nullable=False, unique=True, index=True, default=lambda: str(uuid4())
    )
    tracking_token: Mapped[str] = mapped_column(
        String(80), nullable=False, unique=True, index=True, default=lambda: token_urlsafe(24)
    )
    idempotency_key: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    source_channel: Mapped[str] = mapped_column(
        String(40), nullable=False, default="pedeon", index=True
    )
    external_order_id: Mapped[str | None] = mapped_column(String(120), index=True)
    source_metadata: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    display_number: Mapped[str | None] = mapped_column(String(40), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    payment_status: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    fulfillment_type: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    client_id: Mapped[int | None] = mapped_column(
        ForeignKey("clients.id", ondelete="SET NULL"), index=True
    )
    customer_name: Mapped[str] = mapped_column(String(180), nullable=False)
    customer_phone: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    customer_email: Mapped[str | None] = mapped_column(String(180))
    customer_document: Mapped[str | None] = mapped_column(String(30), index=True)
    delivery_address: Mapped[dict | None] = mapped_column(JSON)
    subtotal_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    delivery_fee_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    customer_notes: Mapped[str | None] = mapped_column(Text)
    internal_notes: Mapped[str | None] = mapped_column(Text)
    sale_id: Mapped[int | None] = mapped_column(
        ForeignKey("sales.id", ondelete="SET NULL"), unique=True, index=True
    )
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    preparation_started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    ready_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    out_for_delivery_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnOrderItem(Base):
    __tablename__ = "pedeon_order_items"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_pedeon_order_item_quantity_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int | None] = mapped_column(
        ForeignKey("products.id", ondelete="SET NULL"), index=True
    )
    publication_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_product_publications.id", ondelete="SET NULL"), index=True
    )
    product_code: Mapped[str | None] = mapped_column(String(80))
    barcode: Mapped[str | None] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(220), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    modifiers_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    customer_notes: Mapped[str | None] = mapped_column(Text)
    fiscal_snapshot: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class PedeOnOrderItemModifier(Base):
    __tablename__ = "pedeon_order_item_modifiers"
    __table_args__ = (
        UniqueConstraint(
            "order_item_id", "option_id", "sequence", name="uq_pedeon_item_modifier_sequence"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    order_item_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_order_items.id", ondelete="CASCADE"), nullable=False, index=True
    )
    group_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_modifier_groups.id", ondelete="SET NULL")
    )
    option_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_modifier_options.id", ondelete="SET NULL")
    )
    group_name: Mapped[str] = mapped_column(String(140), nullable=False)
    option_name: Mapped[str] = mapped_column(String(160), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=1)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=0)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    sequence: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

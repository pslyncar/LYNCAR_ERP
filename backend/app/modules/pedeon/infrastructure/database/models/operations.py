from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
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


class PedeOnStockReservation(Base):
    __tablename__ = "pedeon_stock_reservations"
    __table_args__ = (
        UniqueConstraint(
            "order_item_id", "product_id", name="uq_pedeon_reservation_item_product"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    order_item_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_order_items.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    reservation_type: Mapped[str] = mapped_column(String(20), nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    released_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    release_reason: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class PedeOnDeliveryZone(Base):
    __tablename__ = "pedeon_delivery_zones"
    __table_args__ = (
        UniqueConstraint("store_id", "name", name="uq_pedeon_delivery_zone_name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    match_type: Mapped[str] = mapped_column(String(30), nullable=False)
    postal_code_prefix: Mapped[str | None] = mapped_column(String(8), index=True)
    neighborhood: Mapped[str | None] = mapped_column(String(120), index=True)
    city: Mapped[str | None] = mapped_column(String(120), index=True)
    state: Mapped[str | None] = mapped_column(String(2), index=True)
    center_latitude: Mapped[Decimal | None] = mapped_column(Numeric(10, 7))
    center_longitude: Mapped[Decimal | None] = mapped_column(Numeric(10, 7))
    radius_km: Mapped[Decimal | None] = mapped_column(Numeric(8, 2))
    fee_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    minimum_order_amount: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=0
    )
    free_delivery_threshold: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    estimated_minutes_min: Mapped[int | None] = mapped_column(Integer)
    estimated_minutes_max: Mapped[int | None] = mapped_column(Integer)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnTerminalPermission(Base):
    __tablename__ = "pedeon_terminal_permissions"
    __table_args__ = (
        UniqueConstraint("store_id", "pdv_terminal_id", name="uq_pedeon_store_terminal"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pdv_terminal_id: Mapped[int] = mapped_column(
        ForeignKey("pdv_terminals.id", ondelete="CASCADE"), nullable=False, index=True
    )
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    capabilities: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    station_ids: Mapped[list[int]] = mapped_column(JSON, nullable=False, default=list)
    notification_mode: Mapped[str] = mapped_column(String(30), nullable=False, default="badge")
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    receiver_lease_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), index=True
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnFulfillmentStation(Base):
    __tablename__ = "pedeon_fulfillment_stations"
    __table_args__ = (
        UniqueConstraint("store_id", "code", name="uq_pedeon_station_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(60), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    station_type: Mapped[str] = mapped_column(String(30), nullable=False, default="preparation")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class PedeOnFulfillmentTask(Base):
    __tablename__ = "pedeon_fulfillment_tasks"
    __table_args__ = (
        UniqueConstraint(
            "order_item_id",
            "station_id",
            name="uq_pedeon_task_item_station",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    order_item_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_order_items.id", ondelete="CASCADE"), index=True
    )
    station_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_fulfillment_stations.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    status: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    assigned_terminal_id: Mapped[int | None] = mapped_column(
        ForeignKey("pdv_terminals.id", ondelete="SET NULL"), index=True
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class PedeOnPrintJob(Base):
    __tablename__ = "pedeon_print_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    job_key: Mapped[str] = mapped_column(String(140), nullable=False, unique=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    task_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_fulfillment_tasks.id", ondelete="SET NULL"), index=True
    )
    station_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_fulfillment_stations.id", ondelete="SET NULL"), index=True
    )
    target_terminal_id: Mapped[int | None] = mapped_column(
        ForeignKey("pdv_terminals.id", ondelete="SET NULL"), index=True
    )
    document_type: Mapped[str] = mapped_column(String(40), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending", index=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    available_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    printed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ServiceOrder(Base):
    __tablename__ = "service_orders"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    client_id: Mapped[int] = mapped_column(
        ForeignKey("clients.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    equipment_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("equipments.id", ondelete="SET NULL"),
        index=True,
    )
    ticket_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("tickets.id", ondelete="SET NULL"),
        index=True,
    )
    assigned_user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    opened_by_user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    sold_by_user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True)
    title: Mapped[str] = mapped_column(String(180), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="aberta")
    priority: Mapped[str] = mapped_column(String(20), nullable=False, default="media")
    service_type: Mapped[Optional[str]] = mapped_column(String(80))
    received_equipment: Mapped[Optional[str]] = mapped_column(String(180))
    waiting_reason: Mapped[Optional[str]] = mapped_column(String(220))
    request_description: Mapped[str] = mapped_column(Text, nullable=False)
    technical_diagnosis: Mapped[Optional[str]] = mapped_column(Text)
    service_performed: Mapped[Optional[str]] = mapped_column(Text)
    internal_notes: Mapped[Optional[str]] = mapped_column(Text)
    labor_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    items_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    client = relationship("Client", back_populates="service_orders")
    equipment = relationship("Equipment", back_populates="service_orders")
    ticket = relationship("Ticket", back_populates="service_orders")
    assigned_user = relationship(
        "User",
        back_populates="service_orders",
        foreign_keys=[assigned_user_id],
    )
    opened_by_user = relationship("User", foreign_keys=[opened_by_user_id])
    sold_by_user = relationship("User", foreign_keys=[sold_by_user_id])
    items = relationship(
        "ServiceOrderItem",
        back_populates="service_order",
        cascade="all, delete-orphan",
    )
    events = relationship(
        "ServiceOrderEvent",
        back_populates="service_order",
        cascade="all, delete-orphan",
        order_by="ServiceOrderEvent.created_at.desc()",
    )

    @property
    def opened_by_user_name(self) -> str | None:
        return self.opened_by_user.name if self.opened_by_user else None

    @property
    def opened_by_user_code(self) -> str | None:
        if self.opened_by_user is None:
            return None
        return self.opened_by_user.seller_code or self.opened_by_user.technician_code

    @property
    def assigned_user_name(self) -> str | None:
        return self.assigned_user.name if self.assigned_user else None

    @property
    def assigned_user_code(self) -> str | None:
        if self.assigned_user is None:
            return None
        return self.assigned_user.technician_code or self.assigned_user.seller_code

    @property
    def sold_by_user_name(self) -> str | None:
        return self.sold_by_user.name if self.sold_by_user else None

    @property
    def sold_by_user_code(self) -> str | None:
        if self.sold_by_user is None:
            return None
        return self.sold_by_user.seller_code or self.sold_by_user.technician_code


class ServiceOrderEvent(Base):
    __tablename__ = "service_order_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    service_order_id: Mapped[int] = mapped_column(
        ForeignKey("service_orders.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    event_type: Mapped[str] = mapped_column(String(40), nullable=False)
    status_from: Mapped[Optional[str]] = mapped_column(String(30))
    status_to: Mapped[Optional[str]] = mapped_column(String(30))
    assigned_user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    service_order = relationship("ServiceOrder", back_populates="events")
    user = relationship("User", foreign_keys=[user_id])
    assigned_user = relationship("User", foreign_keys=[assigned_user_id])

    @property
    def user_name(self) -> str | None:
        return self.user.name if self.user else None

    @property
    def assigned_user_name(self) -> str | None:
        return self.assigned_user.name if self.assigned_user else None

    @property
    def assigned_user_code(self) -> str | None:
        if self.assigned_user is None:
            return None
        return self.assigned_user.technician_code or self.assigned_user.seller_code


class ServiceOrderItem(Base):
    __tablename__ = "service_order_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    service_order_id: Mapped[int] = mapped_column(
        ForeignKey("service_orders.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("products.id", ondelete="SET NULL"),
        index=True,
    )
    description: Mapped[str] = mapped_column(String(180), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=1)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    service_order = relationship("ServiceOrder", back_populates="items")
    product = relationship("Product", back_populates="service_order_items")

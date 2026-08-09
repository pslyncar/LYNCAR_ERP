from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ProductionOrder(Base):
    __tablename__ = "production_orders"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    completed_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    canceled_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="planejada")
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    produced_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    total_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    estimated_unit_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    estimated_total_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    due_date: Mapped[Optional[date]] = mapped_column(Date)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    cancellation_reason: Mapped[Optional[str]] = mapped_column(Text)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    canceled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    produced_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )

    product = relationship("Product")
    user = relationship("User", foreign_keys=[user_id])
    completed_by_user = relationship("User", foreign_keys=[completed_by_user_id])
    canceled_by_user = relationship("User", foreign_keys=[canceled_by_user_id])
    components = relationship(
        "ProductionOrderComponent",
        back_populates="production_order",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class ProductionOrderComponent(Base):
    __tablename__ = "production_order_components"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    production_order_id: Mapped[int] = mapped_column(
        ForeignKey("production_orders.id", ondelete="CASCADE"),
        nullable=False,
    )
    component_product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"))
    component_name: Mapped[str] = mapped_column(String(180), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    waste_percent: Mapped[Decimal] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    unit_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    total_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))

    production_order = relationship("ProductionOrder", back_populates="components")
    component_product = relationship("Product")

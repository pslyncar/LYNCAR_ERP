from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ProductCompositionItem(Base):
    __tablename__ = "product_composition_items"
    __table_args__ = (
        UniqueConstraint(
            "product_id",
            "component_product_id",
            name="uq_product_composition_component",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"),
        index=True,
    )
    component_product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"),
        index=True,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    waste_percent: Mapped[Decimal] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    product = relationship(
        "Product",
        back_populates="composition_items",
        foreign_keys=[product_id],
    )
    component_product = relationship(
        "Product",
        back_populates="used_in_compositions",
        foreign_keys=[component_product_id],
    )

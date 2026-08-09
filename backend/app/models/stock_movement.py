from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class StockMovement(Base):
    __tablename__ = "stock_movements"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    movement_type: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    source_type: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    source_id: Mapped[Optional[int]] = mapped_column(index=True)
    source_number: Mapped[Optional[str]] = mapped_column(String(40), index=True)
    quantity_delta: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    quantity_before: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    quantity_after: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_price: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    total_value: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    reason: Mapped[Optional[str]] = mapped_column(String(180))
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )

    product = relationship("Product", back_populates="stock_movements")
    user = relationship("User")

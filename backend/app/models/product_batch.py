from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ProductBatch(Base):
    __tablename__ = "product_batches"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    batch_number: Mapped[str | None] = mapped_column(String(80), index=True)
    expiration_date: Mapped[date | None] = mapped_column(Date, index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    source_type: Mapped[str | None] = mapped_column(String(40), index=True)
    source_id: Mapped[int | None] = mapped_column(index=True)
    source_number: Mapped[str | None] = mapped_column(String(60), index=True)
    supplier_name: Mapped[str | None] = mapped_column(String(180))
    invoice_number: Mapped[str | None] = mapped_column(String(30))
    invoice_series: Mapped[str | None] = mapped_column(String(20))
    notes: Mapped[str | None] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    product = relationship("Product", back_populates="batches")

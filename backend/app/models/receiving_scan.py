from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ReceivingScan(Base):
    __tablename__ = "receiving_scans"
    __table_args__ = (UniqueConstraint("idempotency_key", name="uq_receiving_scan_idempotency"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("receiving_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    stock_entry_item_id: Mapped[int | None] = mapped_column(ForeignKey("stock_entry_items.id", ondelete="SET NULL"), index=True)
    idempotency_key: Mapped[str] = mapped_column(String(120), nullable=False)
    barcode: Mapped[str | None] = mapped_column(String(80), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    batch_number: Mapped[str | None] = mapped_column(String(80))
    expiration_date: Mapped[date | None] = mapped_column(Date)
    condition: Mapped[str] = mapped_column(String(30), nullable=False, default="ok")
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    session = relationship("ReceivingSession", back_populates="scans")
    stock_entry_item = relationship("StockEntryItem")

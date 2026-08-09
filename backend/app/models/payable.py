from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Payable(Base):
    __tablename__ = "payables"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    supplier_id: Mapped[Optional[int]] = mapped_column(ForeignKey("suppliers.id", ondelete="SET NULL"), index=True)
    stock_entry_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stock_entries.id", ondelete="SET NULL"), index=True)
    description: Mapped[str] = mapped_column(String(220), nullable=False)
    document_number: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    category: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    original_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    paid_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    balance_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="open", index=True)
    issue_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    due_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), index=True)
    competence_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    settled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    notes: Mapped[Optional[str]] = mapped_column(Text)

    supplier = relationship("Supplier", lazy="selectin")
    stock_entry = relationship("StockEntry", lazy="selectin")
    payments = relationship(
        "PayablePayment",
        back_populates="payable",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    @property
    def supplier_name(self) -> str | None:
        return self.supplier.name if self.supplier is not None else None

    @property
    def stock_entry_number(self) -> str | None:
        if self.stock_entry is None:
            return None
        return self.stock_entry.invoice_number or f"ENT{self.stock_entry.id}"


class PayablePayment(Base):
    __tablename__ = "payable_payments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    payable_id: Mapped[int] = mapped_column(ForeignKey("payables.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    method: Mapped[str] = mapped_column(String(30), nullable=False, default="dinheiro")
    notes: Mapped[Optional[str]] = mapped_column(Text)
    paid_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    payable = relationship("Payable", back_populates="payments")

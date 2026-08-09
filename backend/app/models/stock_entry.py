from datetime import datetime
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class StockEntry(Base):
    __tablename__ = "stock_entries"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    supplier_id: Mapped[int | None] = mapped_column(ForeignKey("suppliers.id", ondelete="SET NULL"), index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    source: Mapped[str] = mapped_column(String(30), nullable=False, default="manual")
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="confirmed")
    invoice_key: Mapped[str | None] = mapped_column(String(60), index=True)
    invoice_number: Mapped[str | None] = mapped_column(String(30))
    invoice_series: Mapped[str | None] = mapped_column(String(20))
    supplier_name: Mapped[str | None] = mapped_column(String(180))
    supplier_document: Mapped[str | None] = mapped_column(String(30))
    total_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False, default=0)
    notes: Mapped[str | None] = mapped_column(Text)
    issued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    supplier = relationship("Supplier", back_populates="stock_entries")
    user = relationship("User")
    items = relationship("StockEntryItem", back_populates="entry", cascade="all, delete-orphan")


class StockEntryItem(Base):
    __tablename__ = "stock_entry_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stock_entry_id: Mapped[int] = mapped_column(ForeignKey("stock_entries.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    description: Mapped[str] = mapped_column(String(220), nullable=False)
    barcode: Mapped[str | None] = mapped_column(String(80), index=True)
    invoice_quantity: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    invoice_unit: Mapped[str | None] = mapped_column(String(20))
    package_conversion_factor: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    received_quantity: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    total_cost: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    ncm: Mapped[str | None] = mapped_column(String(20))
    cfop: Mapped[str | None] = mapped_column(String(10))
    origin: Mapped[str | None] = mapped_column(String(2))
    cst: Mapped[str | None] = mapped_column(String(10))
    csosn: Mapped[str | None] = mapped_column(String(10))
    icms_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    pis_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    cofins_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ipi_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_cbs_cst: Mapped[str | None] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[str | None] = mapped_column(String(20))
    cbs_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_state_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_city_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    selective_tax_cst: Mapped[str | None] = mapped_column(String(10))
    selective_tax_classification: Mapped[str | None] = mapped_column(String(20))
    selective_tax_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    batch_number: Mapped[str | None] = mapped_column(String(80))
    expiration_date: Mapped[datetime | None] = mapped_column(Date)
    check_status: Mapped[str] = mapped_column(String(30), nullable=False, default="accepted")
    check_notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    entry = relationship("StockEntry", back_populates="items")
    product = relationship("Product")

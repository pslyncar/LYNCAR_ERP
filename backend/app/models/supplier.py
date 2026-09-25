from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Supplier(Base):
    __tablename__ = "suppliers"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(180), nullable=False)
    trade_name: Mapped[str | None] = mapped_column(String(180))
    document_number: Mapped[str | None] = mapped_column(String(30), index=True)
    state_registration: Mapped[str | None] = mapped_column(String(40))
    phone: Mapped[str | None] = mapped_column(String(40))
    email: Mapped[str | None] = mapped_column(String(180))
    address_line: Mapped[str | None] = mapped_column(String(180))
    address_number: Mapped[str | None] = mapped_column(String(20))
    address_complement: Mapped[str | None] = mapped_column(String(120))
    neighborhood: Mapped[str | None] = mapped_column(String(120))
    city: Mapped[str | None] = mapped_column(String(120))
    state: Mapped[str | None] = mapped_column(String(2))
    city_code: Mapped[str | None] = mapped_column(String(20))
    zip_code: Mapped[str | None] = mapped_column(String(20))
    notes: Mapped[str | None] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    stock_entries = relationship("StockEntry", back_populates="supplier")
    product_links = relationship("SupplierProductLink", back_populates="supplier", cascade="all, delete-orphan")

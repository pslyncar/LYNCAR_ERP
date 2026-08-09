from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Sale(Base):
    __tablename__ = "sales"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    client_id: Mapped[Optional[int]] = mapped_column(ForeignKey("clients.id", ondelete="SET NULL"))
    seller_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    source: Mapped[str] = mapped_column(String(20), nullable=False, default="pdv")
    cash_register_number: Mapped[Optional[str]] = mapped_column(String(10), index=True)
    cash_session_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("pdv_cash_sessions.id", ondelete="SET NULL"),
        index=True,
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="finalizada")
    subtotal_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    amount_paid: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    change_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    consumer_cpf: Mapped[Optional[str]] = mapped_column(String(14), index=True)
    offline_client_id: Mapped[Optional[str]] = mapped_column(String(80), unique=True, index=True)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    sold_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    canceled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    client = relationship("Client", back_populates="sales")
    seller = relationship("User", back_populates="sales")
    cash_session = relationship("PdvCashSession")
    items = relationship(
        "SaleItem",
        back_populates="sale",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    payments = relationship(
        "SalePayment",
        back_populates="sale",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    fiscal_documents = relationship("FiscalDocument", back_populates="sale", lazy="selectin")

    @property
    def seller_name(self) -> str | None:
        return self.seller.name if self.seller is not None else None

    @property
    def has_fiscal_document(self) -> bool:
        return bool(self.fiscal_documents)

    @property
    def has_authorized_fiscal_document(self) -> bool:
        return any(
            document.status == "authorized"
            for document in self.fiscal_documents
        )


class SaleItem(Base):
    __tablename__ = "sale_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sale_id: Mapped[int] = mapped_column(ForeignKey("sales.id", ondelete="CASCADE"), nullable=False)
    product_id: Mapped[Optional[int]] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"))
    description: Mapped[str] = mapped_column(String(220), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=1)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    barcode: Mapped[Optional[str]] = mapped_column(String(80))

    sale = relationship("Sale", back_populates="items")
    product = relationship("Product", back_populates="sale_items")


class SalePayment(Base):
    __tablename__ = "sale_payments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sale_id: Mapped[int] = mapped_column(ForeignKey("sales.id", ondelete="CASCADE"), nullable=False)
    method: Mapped[str] = mapped_column(String(30), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    authorization_code: Mapped[Optional[str]] = mapped_column(String(80))
    notes: Mapped[Optional[str]] = mapped_column(Text)

    sale = relationship("Sale", back_populates="payments")

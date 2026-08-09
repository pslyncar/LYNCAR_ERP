from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Receivable(Base):
    __tablename__ = "receivables"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    sale_id: Mapped[Optional[int]] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), index=True)
    client_id: Mapped[Optional[int]] = mapped_column(ForeignKey("clients.id", ondelete="SET NULL"), index=True)
    description: Mapped[str] = mapped_column(String(220), nullable=False)
    original_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    paid_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    balance_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="open", index=True)
    due_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    settled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    notes: Mapped[Optional[str]] = mapped_column(Text)

    payments = relationship(
        "ReceivablePayment",
        back_populates="receivable",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    client = relationship("Client", lazy="selectin")
    sale = relationship("Sale", lazy="selectin")

    @property
    def client_name(self) -> str | None:
        return self.client.name if self.client is not None else None

    @property
    def sale_number(self) -> str | None:
        return self.sale.number if self.sale is not None else None

    @property
    def sale_sold_at(self) -> datetime | None:
        return self.sale.sold_at if self.sale is not None else None

    @property
    def sale_items(self) -> list[dict[str, object]]:
        if self.sale is None:
            return []
        return [
            {
                "id": item.id,
                "description": item.description,
                "quantity": item.quantity,
                "unit": item.unit,
                "unit_price": item.unit_price,
                "total_price": item.total_price,
            }
            for item in self.sale.items
        ]


class ReceivablePayment(Base):
    __tablename__ = "receivable_payments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    receivable_id: Mapped[int] = mapped_column(ForeignKey("receivables.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    method: Mapped[str] = mapped_column(String(30), nullable=False, default="dinheiro")
    notes: Mapped[Optional[str]] = mapped_column(Text)
    paid_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    receivable = relationship("Receivable", back_populates="payments")

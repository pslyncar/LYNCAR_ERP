from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class CashClosing(Base):
    __tablename__ = "cash_closings"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    cash_session_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("pdv_cash_sessions.id", ondelete="SET NULL"),
        index=True,
    )
    cash_register_number: Mapped[Optional[str]] = mapped_column(String(10), index=True)
    operator_name: Mapped[Optional[str]] = mapped_column(String(150))
    opened_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
    business_date: Mapped[Optional[date]] = mapped_column(Date)
    crossed_business_day: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
    )
    business_day_cutoff_minutes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=180,
    )
    opened_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    closed_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    opening_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    expected_cash_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    counted_cash_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    cash_difference_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_sales_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_sales_count: Mapped[int] = mapped_column(nullable=False, default=0)
    total_withdrawal_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_supply_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    authorized_by_operator_id: Mapped[Optional[int]] = mapped_column()
    authorized_by_operator_name: Mapped[Optional[str]] = mapped_column(String(150))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending_treasury")
    treasury_checked_by_user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    treasury_checked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    treasury_notes: Mapped[Optional[str]] = mapped_column(Text)
    notes: Mapped[Optional[str]] = mapped_column(Text)

    payments = relationship(
        "CashClosingPayment",
        back_populates="closing",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    movements = relationship(
        "CashClosingMovement",
        back_populates="closing",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class CashClosingPayment(Base):
    __tablename__ = "cash_closing_payments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    closing_id: Mapped[int] = mapped_column(ForeignKey("cash_closings.id", ondelete="CASCADE"))
    method: Mapped[str] = mapped_column(String(30), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)

    closing = relationship("CashClosing", back_populates="payments")


class CashClosingMovement(Base):
    __tablename__ = "cash_closing_movements"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    closing_id: Mapped[int] = mapped_column(ForeignKey("cash_closings.id", ondelete="CASCADE"))
    movement_type: Mapped[str] = mapped_column(String(30), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    reason: Mapped[Optional[str]] = mapped_column(String(220))
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    authorized_by_operator_id: Mapped[Optional[int]] = mapped_column()
    authorized_by_operator_name: Mapped[Optional[str]] = mapped_column(String(150))

    closing = relationship("CashClosing", back_populates="movements")

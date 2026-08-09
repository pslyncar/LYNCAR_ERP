from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class PdvCashSession(Base):
    __tablename__ = "pdv_cash_sessions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    cash_register_number: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    terminal_key: Mapped[Optional[str]] = mapped_column(String(180), index=True)
    operator_id: Mapped[Optional[int]] = mapped_column(ForeignKey("pdv_operators.id", ondelete="SET NULL"))
    operator_name: Mapped[Optional[str]] = mapped_column(String(150))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="open", index=True)
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    opening_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    closing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("cash_closings.id", ondelete="SET NULL"))
    last_heartbeat_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[Optional[str]] = mapped_column(Text)
    created_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    closed_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))

    operator = relationship("PdvOperator")
    closing = relationship("CashClosing", foreign_keys=[closing_id])

from datetime import datetime

from decimal import Decimal

from sqlalchemy import Boolean, DateTime, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PdvTerminal(Base):
    __tablename__ = "pdv_terminals"
    __table_args__ = (
        UniqueConstraint("cash_register_number", name="uq_pdv_terminal_cash_register_number"),
        UniqueConstraint("terminal_key", name="uq_pdv_terminal_terminal_key"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    cash_register_number: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    terminal_key: Mapped[str] = mapped_column(String(180), nullable=False, index=True)
    app_version: Mapped[str | None] = mapped_column(String(40))
    device_label: Mapped[str | None] = mapped_column(String(120))
    activation_code_hash: Mapped[str | None] = mapped_column(String(180), index=True)
    activation_code_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    activation_status: Mapped[str] = mapped_column(String(30), nullable=False, default="active")
    machine_name: Mapped[str | None] = mapped_column(String(120))
    windows_user: Mapped[str | None] = mapped_column(String(120))
    windows_version: Mapped[str | None] = mapped_column(String(120))
    device_fingerprint: Mapped[str | None] = mapped_column(String(180), index=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    current_status: Mapped[str | None] = mapped_column(String(30))
    current_operator_name: Mapped[str | None] = mapped_column(String(150))
    cash_opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    current_session_total_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)

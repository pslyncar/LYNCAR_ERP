from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PdvOperator(Base):
    __tablename__ = "pdv_operators"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    code: Mapped[str] = mapped_column(String(30), nullable=False, unique=True, index=True)
    pin_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, default="operator")
    can_open_cash: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    can_authorize_withdrawal: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    can_authorize_cancel: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    can_authorize_discount: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ReceivingSession(Base):
    __tablename__ = "receiving_sessions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stock_entry_id: Mapped[int] = mapped_column(ForeignKey("stock_entries.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    device_id: Mapped[str | None] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active", index=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    stock_entry = relationship("StockEntry")
    user = relationship("User")
    scans = relationship("ReceivingScan", back_populates="session", cascade="all, delete-orphan")

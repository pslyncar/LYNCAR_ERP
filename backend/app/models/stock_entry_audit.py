from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class StockEntryAuditEvent(Base):
    __tablename__ = "stock_entry_audit_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stock_entry_id: Mapped[int] = mapped_column(
        ForeignKey("stock_entries.id", ondelete="CASCADE"), index=True, nullable=False
    )
    stock_entry_item_id: Mapped[int | None] = mapped_column(
        ForeignKey("stock_entry_items.id", ondelete="SET NULL"), index=True
    )
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    source: Mapped[str] = mapped_column(String(30), nullable=False, default="web")
    reason: Mapped[str | None] = mapped_column(Text)
    old_value: Mapped[str | None] = mapped_column(Text)
    new_value: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    stock_entry = relationship("StockEntry")
    stock_entry_item = relationship("StockEntryItem")
    user = relationship("User")

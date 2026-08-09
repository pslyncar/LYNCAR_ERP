from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class XmlInboxMessage(Base):
    __tablename__ = "xml_inbox_messages"

    id: Mapped[int] = mapped_column(primary_key=True)
    stock_entry_id: Mapped[int | None] = mapped_column(
        ForeignKey("stock_entries.id", ondelete="SET NULL"),
        index=True,
    )
    status: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    sender_email: Mapped[str | None] = mapped_column(String(180))
    subject: Mapped[str | None] = mapped_column(String(240))
    attachment_name: Mapped[str | None] = mapped_column(String(240))
    supplier_name: Mapped[str | None] = mapped_column(String(180))
    supplier_document: Mapped[str | None] = mapped_column(String(30), index=True)
    recipient_document: Mapped[str | None] = mapped_column(String(30), index=True)
    invoice_key: Mapped[str | None] = mapped_column(String(60), index=True)
    invoice_number: Mapped[str | None] = mapped_column(String(30))
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    xml_content: Mapped[str | None] = mapped_column(Text)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

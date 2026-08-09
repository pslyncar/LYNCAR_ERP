from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.master_database import MasterBase


class MasterSupportTicket(MasterBase):
    __tablename__ = "master_support_tickets"

    id: Mapped[int] = mapped_column(primary_key=True)
    company_id: Mapped[int] = mapped_column(
        ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    company_code: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    company_name: Mapped[str] = mapped_column(String(180), nullable=False)
    module: Mapped[str] = mapped_column(String(40), nullable=False, default="outro")
    priority: Mapped[str] = mapped_column(String(20), nullable=False, default="normal")
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="aberto")
    subject: Mapped[str] = mapped_column(String(180), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    requester_user_id: Mapped[int | None] = mapped_column(Integer)
    requester_name: Mapped[str | None] = mapped_column(String(150))
    requester_email: Mapped[str | None] = mapped_column(String(180))
    customer_attachments_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    assigned_master_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("master_users.id", ondelete="SET NULL"),
        index=True,
    )
    first_response_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_message_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    company = relationship("Company")
    assigned_master_user = relationship("MasterUser")
    messages = relationship(
        "MasterSupportMessage",
        back_populates="ticket",
        cascade="all, delete-orphan",
        order_by="MasterSupportMessage.created_at",
    )

    @property
    def assigned_master_user_name(self) -> str | None:
        return self.assigned_master_user.name if self.assigned_master_user else None

    @property
    def assigned_master_user_email(self) -> str | None:
        return self.assigned_master_user.email if self.assigned_master_user else None


class MasterSupportMessage(MasterBase):
    __tablename__ = "master_support_messages"

    id: Mapped[int] = mapped_column(primary_key=True)
    ticket_id: Mapped[int] = mapped_column(
        ForeignKey("master_support_tickets.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    author_type: Mapped[str] = mapped_column(String(20), nullable=False)
    author_user_id: Mapped[int | None] = mapped_column(Integer)
    author_name: Mapped[str | None] = mapped_column(String(150))
    author_email: Mapped[str | None] = mapped_column(String(180))
    body: Mapped[str] = mapped_column(Text, nullable=False)
    attachment_url: Mapped[str | None] = mapped_column(Text)
    attachment_name: Mapped[str | None] = mapped_column(String(220))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    ticket = relationship("MasterSupportTicket", back_populates="messages")

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class CompanyPresence(MasterBase):
    __tablename__ = "company_presence"
    __table_args__ = (
        UniqueConstraint(
            "company_code",
            "user_id",
            "client_type",
            name="uq_company_presence_company_user_client",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    company_code: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    company_name: Mapped[str | None] = mapped_column(String(180))
    user_id: Mapped[int] = mapped_column(Integer, nullable=False)
    user_name: Mapped[str | None] = mapped_column(String(150))
    user_email: Mapped[str | None] = mapped_column(String(180), index=True)
    user_role: Mapped[str | None] = mapped_column(String(30))
    client_type: Mapped[str] = mapped_column(String(30), nullable=False, default="web")
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

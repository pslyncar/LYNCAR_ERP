from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterUserIndex(MasterBase):
    __tablename__ = "master_user_index"
    __table_args__ = (
        UniqueConstraint("company_code", "email", name="uq_master_user_index_company_email"),
        UniqueConstraint("email", name="uq_master_user_index_email"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    company_code: Mapped[str] = mapped_column(String(64), index=True)
    company_name: Mapped[str] = mapped_column(String(180))
    user_id: Mapped[int | None] = mapped_column()
    name: Mapped[str] = mapped_column(String(150))
    email: Mapped[str] = mapped_column(String(180), index=True)
    role: Mapped[str] = mapped_column(String(40))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterEmailSetting(MasterBase):
    __tablename__ = "master_email_settings"

    provider: Mapped[str] = mapped_column(String(40), primary_key=True)
    auth_method: Mapped[str] = mapped_column(String(30), nullable=False, default="smtp")
    smtp_host: Mapped[str | None] = mapped_column(String(180), nullable=True)
    smtp_port: Mapped[int] = mapped_column(Integer, nullable=False, default=587)
    username: Mapped[str | None] = mapped_column(String(180), nullable=True)
    password_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    client_id: Mapped[str | None] = mapped_column(String(240), nullable=True)
    client_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    refresh_token_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    from_email: Mapped[str | None] = mapped_column(String(180), nullable=True)
    from_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

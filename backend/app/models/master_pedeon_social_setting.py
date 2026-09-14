from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterPedeonSocialSetting(MasterBase):
    """OAuth settings for customer accounts in the public PedeOn catalog."""

    __tablename__ = "master_pedeon_social_settings"

    provider: Mapped[str] = mapped_column(String(20), primary_key=True)
    client_id: Mapped[str | None] = mapped_column(String(240), nullable=True)
    client_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    redirect_uri: Mapped[str | None] = mapped_column(String(500), nullable=True)
    extra_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    enabled: Mapped[bool] = mapped_column(default=False, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

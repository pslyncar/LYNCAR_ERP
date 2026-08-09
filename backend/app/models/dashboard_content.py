from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class DashboardContent(MasterBase):
    __tablename__ = "dashboard_contents"

    id: Mapped[int] = mapped_column(primary_key=True)
    content_type: Mapped[str] = mapped_column(String(30), nullable=False, default="notice")
    title: Mapped[str] = mapped_column(String(180), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    badge: Mapped[str | None] = mapped_column(String(80))
    price_label: Mapped[str | None] = mapped_column(String(80))
    image_url: Mapped[str | None] = mapped_column(Text)
    target_url: Mapped[str | None] = mapped_column(Text)
    button_label: Mapped[str | None] = mapped_column(String(80))
    segment: Mapped[str | None] = mapped_column(String(60), index=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
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

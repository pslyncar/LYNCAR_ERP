from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterHoliday(MasterBase):
    __tablename__ = "master_holidays"
    __table_args__ = (
        UniqueConstraint(
            "holiday_date",
            "description",
            "holiday_type",
            "city",
            "state",
            name="uq_master_holiday_identity",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    holiday_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    description: Mapped[str] = mapped_column(String(180), nullable=False)
    holiday_type: Mapped[str] = mapped_column(String(30), nullable=False, default="nacional")
    city: Mapped[str | None] = mapped_column(String(120), index=True)
    city_code: Mapped[str | None] = mapped_column(String(20), index=True)
    state: Mapped[str | None] = mapped_column(String(2), index=True)
    source: Mapped[str | None] = mapped_column(String(80))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class MasterHolidaySync(MasterBase):
    __tablename__ = "master_holiday_syncs"
    __table_args__ = (
        UniqueConstraint(
            "year",
            "city",
            "state",
            "holiday_type",
            name="uq_master_holiday_sync_scope",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    year: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    city: Mapped[str | None] = mapped_column(String(120), index=True)
    city_code: Mapped[str | None] = mapped_column(String(20), index=True)
    state: Mapped[str | None] = mapped_column(String(2), index=True)
    holiday_type: Mapped[str] = mapped_column(String(30), nullable=False, default="nacional")
    source: Mapped[str | None] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending")
    message: Mapped[str | None] = mapped_column(Text)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

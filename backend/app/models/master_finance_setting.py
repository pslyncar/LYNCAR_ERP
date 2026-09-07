from datetime import datetime

from sqlalchemy import Boolean, DateTime, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterFinanceSetting(MasterBase):
    __tablename__ = "master_finance_settings"

    id: Mapped[int] = mapped_column(primary_key=True, default=1)
    late_charges_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    late_fee_percent: Mapped[float] = mapped_column(Numeric(5, 2), default=0, nullable=False)
    late_interest_daily_percent: Mapped[float] = mapped_column(Numeric(7, 4), default=0, nullable=False)
    late_grace_days: Mapped[int] = mapped_column(default=0, nullable=False)
    monetary_correction_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    monetary_index: Mapped[str] = mapped_column(String(20), default="IPCA", nullable=False)
    automatic_index_update: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

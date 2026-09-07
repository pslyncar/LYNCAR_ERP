from datetime import datetime

from sqlalchemy import DateTime, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterEconomicIndex(MasterBase):
    """Official monthly economic indexes used by the billing engine."""

    __tablename__ = "master_economic_indices"
    __table_args__ = (UniqueConstraint("index_name", "reference_month"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    index_name: Mapped[str] = mapped_column(String(20), default="IPCA", index=True)
    reference_month: Mapped[str] = mapped_column(String(7), index=True)
    percentage: Mapped[float] = mapped_column(Numeric(8, 4), nullable=False)
    source: Mapped[str] = mapped_column(String(120), default="IBGE SIDRA", nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

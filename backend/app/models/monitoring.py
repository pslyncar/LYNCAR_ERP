from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class MonitoringSnapshot(Base):
    __tablename__ = "monitoring_snapshots"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    equipment_id: Mapped[int] = mapped_column(
        ForeignKey("equipments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    cpu_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    memory_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    disk_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    temperature_celsius: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2))
    collected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    equipment = relationship("Equipment", back_populates="monitoring_snapshots")


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    equipment_id: Mapped[int] = mapped_column(
        ForeignKey("equipments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    severity: Mapped[str] = mapped_column(String(20), nullable=False, default="warning")
    message: Mapped[str] = mapped_column(String(255), nullable=False)
    metric_value: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    resolved: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    equipment = relationship("Equipment", back_populates="alerts")

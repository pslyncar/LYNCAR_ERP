from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, JSON, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class EquipmentCurrentStatus(Base):
    __tablename__ = "equipment_current_status"

    equipment_id: Mapped[int] = mapped_column(
        ForeignKey("equipments.id", ondelete="CASCADE"),
        primary_key=True,
    )
    cpu_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    memory_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    disk_usage_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    storage_volumes: Mapped[list[dict]] = mapped_column(JSON, nullable=False, default=list)
    temperature_celsius: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2))
    health_status: Mapped[str] = mapped_column(String(20), nullable=False, default="ok")
    collected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    equipment = relationship("Equipment", back_populates="current_status")

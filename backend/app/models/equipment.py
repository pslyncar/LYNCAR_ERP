from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Equipment(Base):
    __tablename__ = "equipments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    client_id: Mapped[int] = mapped_column(
        ForeignKey("clients.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    hostname: Mapped[str] = mapped_column(String(150), nullable=False)
    asset_tag: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    location: Mapped[Optional[str]] = mapped_column(String(120))
    responsible_user: Mapped[Optional[str]] = mapped_column(String(150))
    operating_system: Mapped[Optional[str]] = mapped_column(String(150))
    processor: Mapped[Optional[str]] = mapped_column(String(180))
    ram_total_gb: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    storage_total_gb: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="ativo")
    technical_notes: Mapped[Optional[str]] = mapped_column(Text)
    agent_token_hash: Mapped[Optional[str]] = mapped_column(Text)
    agent_version: Mapped[Optional[str]] = mapped_column(String(40))
    last_ip_address: Mapped[Optional[str]] = mapped_column(String(60))
    last_logged_user: Mapped[Optional[str]] = mapped_column(String(150))
    last_seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    client = relationship("Client", back_populates="equipments")
    tickets = relationship("Ticket", back_populates="equipment")
    service_orders = relationship("ServiceOrder", back_populates="equipment")
    monitoring_snapshots = relationship(
        "MonitoringSnapshot",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )
    current_status = relationship(
        "EquipmentCurrentStatus",
        back_populates="equipment",
        cascade="all, delete-orphan",
        uselist=False,
    )
    alerts = relationship(
        "Alert",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )

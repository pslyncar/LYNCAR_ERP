from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class StorageVolumeRead(BaseModel):
    device: str | None = None
    mountpoint: str
    filesystem: str | None = None
    total_gb: Decimal
    used_gb: Decimal
    free_gb: Decimal
    usage_percent: Decimal = Field(ge=0, le=100)


class MonitoringSnapshotCreate(BaseModel):
    equipment_id: int
    cpu_usage_percent: Decimal = Field(ge=0, le=100)
    memory_usage_percent: Decimal = Field(ge=0, le=100)
    disk_usage_percent: Decimal = Field(ge=0, le=100)
    storage_volumes: list[StorageVolumeRead] = Field(default_factory=list)
    temperature_celsius: Decimal | None = Field(default=None, ge=-50, le=150)
    collected_at: datetime
    hostname: str | None = Field(default=None, max_length=150)
    operating_system: str | None = Field(default=None, max_length=150)
    ip_address: str | None = Field(default=None, max_length=60)
    agent_version: str | None = Field(default=None, max_length=40)
    logged_user: str | None = Field(default=None, max_length=150)


class MonitoringSnapshotRead(MonitoringSnapshotCreate):
    id: int
    received_at: datetime

    model_config = ConfigDict(from_attributes=True)

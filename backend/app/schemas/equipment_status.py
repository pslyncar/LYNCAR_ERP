from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class EquipmentCurrentStatusRead(BaseModel):
    equipment_id: int
    cpu_usage_percent: Decimal
    memory_usage_percent: Decimal
    disk_usage_percent: Decimal
    storage_volumes: list[dict]
    temperature_celsius: Decimal | None
    health_status: str
    collected_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AlertRead(BaseModel):
    id: int
    equipment_id: int
    type: str
    severity: str
    message: str
    metric_value: Decimal
    resolved: bool
    created_at: datetime
    resolved_at: datetime | None

    model_config = ConfigDict(from_attributes=True)

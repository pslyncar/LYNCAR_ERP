from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

EquipmentStatus = Literal["ativo", "inativo", "manutencao", "offline"]


class EquipmentBase(BaseModel):
    client_id: int
    hostname: str = Field(min_length=1, max_length=150)
    asset_tag: str | None = Field(default=None, max_length=80)
    location: str | None = Field(default=None, max_length=120)
    responsible_user: str | None = Field(default=None, max_length=150)
    operating_system: str | None = Field(default=None, max_length=150)
    processor: str | None = Field(default=None, max_length=180)
    ram_total_gb: Decimal | None = Field(default=None, ge=0)
    storage_total_gb: Decimal | None = Field(default=None, ge=0)
    status: EquipmentStatus = "ativo"
    technical_notes: str | None = None


class EquipmentCreate(EquipmentBase):
    pass


class EquipmentUpdate(BaseModel):
    client_id: int | None = None
    hostname: str | None = Field(default=None, min_length=1, max_length=150)
    asset_tag: str | None = Field(default=None, max_length=80)
    location: str | None = Field(default=None, max_length=120)
    responsible_user: str | None = Field(default=None, max_length=150)
    operating_system: str | None = Field(default=None, max_length=150)
    processor: str | None = Field(default=None, max_length=180)
    ram_total_gb: Decimal | None = Field(default=None, ge=0)
    storage_total_gb: Decimal | None = Field(default=None, ge=0)
    status: EquipmentStatus | None = None
    technical_notes: str | None = None


class EquipmentRead(EquipmentBase):
    id: int
    agent_version: str | None
    last_ip_address: str | None
    last_logged_user: str | None
    last_seen_at: datetime | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class EquipmentAgentTokenRead(BaseModel):
    equipment_id: int
    token: str
    message: str

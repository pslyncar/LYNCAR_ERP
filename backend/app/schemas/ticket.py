from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

TicketPriority = Literal["baixa", "media", "alta"]
TicketStatus = Literal["aberto", "em_andamento", "concluido", "cancelado"]


class TicketBase(BaseModel):
    client_id: int
    equipment_id: int | None = None
    title: str = Field(min_length=3, max_length=180)
    description: str = Field(min_length=3)
    solution: str | None = None
    status: TicketStatus = "aberto"
    priority: TicketPriority = "media"
    assigned_user_id: int | None = None


class TicketCreate(TicketBase):
    pass


class TicketUpdate(BaseModel):
    client_id: int | None = None
    equipment_id: int | None = None
    title: str | None = Field(default=None, min_length=3, max_length=180)
    description: str | None = Field(default=None, min_length=3)
    solution: str | None = None
    status: TicketStatus | None = None
    priority: TicketPriority | None = None
    assigned_user_id: int | None = None


class TicketRead(TicketBase):
    id: int
    opened_at: datetime
    closed_at: datetime | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

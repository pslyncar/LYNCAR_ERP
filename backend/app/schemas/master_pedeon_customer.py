from datetime import datetime

from pydantic import BaseModel


class MasterPedeOnCustomerRead(BaseModel):
    id: int
    email: str
    name: str
    phone: str | None = None
    active: bool
    blocked_at: datetime | None = None
    linked_stores: int = 0
    created_at: datetime


class MasterPedeOnCustomerStatusUpdate(BaseModel):
    active: bool

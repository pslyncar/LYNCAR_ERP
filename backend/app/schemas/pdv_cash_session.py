from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

PdvCashSessionStatus = Literal["open", "closed", "crashed", "recovered"]


class PdvCashSessionOpen(BaseModel):
    cash_register_number: str = Field(min_length=1, max_length=10)
    terminal_key: str | None = Field(default=None, max_length=180)
    operator_id: int | None = None
    operator_name: str | None = Field(default=None, max_length=150)
    opening_amount: Decimal = Field(default=0, ge=0)


class PdvCashSessionHeartbeat(BaseModel):
    last_error: str | None = None


class PdvCashSessionClose(BaseModel):
    closing_id: int | None = None


class PdvCashSessionRead(BaseModel):
    id: int
    cash_register_number: str
    terminal_key: str | None
    operator_id: int | None
    operator_name: str | None
    status: PdvCashSessionStatus
    opened_at: datetime
    closed_at: datetime | None
    opening_amount: Decimal
    closing_id: int | None
    last_heartbeat_at: datetime | None
    last_error: str | None

    model_config = ConfigDict(from_attributes=True)

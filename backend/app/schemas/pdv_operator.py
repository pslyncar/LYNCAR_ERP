from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

PdvOperatorRole = Literal["operator", "fiscal"]
PdvAuthorizationAction = Literal[
    "authorize_open_cash",
    "authorize_close_cash",
    "open_cash",
    "withdrawal",
    "cancel_sale",
    "discount",
]


class PdvOperatorCreate(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    code: str = Field(min_length=2, max_length=30)
    pin: str = Field(min_length=4, max_length=30)
    role: PdvOperatorRole = "operator"
    can_open_cash: bool = True
    can_authorize_withdrawal: bool = False
    can_authorize_cancel: bool = False
    can_authorize_discount: bool = False
    active: bool = True
    notes: str | None = None


class PdvOperatorUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=150)
    code: str | None = Field(default=None, min_length=2, max_length=30)
    pin: str | None = Field(default=None, min_length=4, max_length=30)
    role: PdvOperatorRole | None = None
    can_open_cash: bool | None = None
    can_authorize_withdrawal: bool | None = None
    can_authorize_cancel: bool | None = None
    can_authorize_discount: bool | None = None
    active: bool | None = None
    notes: str | None = None


class PdvOperatorRead(BaseModel):
    id: int
    name: str
    code: str
    role: str
    can_open_cash: bool
    can_authorize_withdrawal: bool
    can_authorize_cancel: bool
    can_authorize_discount: bool
    active: bool
    notes: str | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PdvAuthorizationRequest(BaseModel):
    code: str = Field(min_length=1, max_length=30)
    pin: str = Field(min_length=1, max_length=30)
    action: PdvAuthorizationAction


class PdvAuthorizationResponse(BaseModel):
    authorized: bool
    operator_id: int
    operator_name: str
    role: str
    message: str

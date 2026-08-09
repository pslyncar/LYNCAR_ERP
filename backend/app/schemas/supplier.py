from datetime import datetime

from pydantic import BaseModel, Field


class SupplierCreate(BaseModel):
    name: str = Field(min_length=2, max_length=180)
    trade_name: str | None = Field(default=None, max_length=180)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=180)
    address_line: str | None = Field(default=None, max_length=180)
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, max_length=2)
    notes: str | None = None
    active: bool = True


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=180)
    trade_name: str | None = Field(default=None, max_length=180)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=180)
    address_line: str | None = Field(default=None, max_length=180)
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, max_length=2)
    notes: str | None = None
    active: bool | None = None


class SupplierRead(SupplierCreate):
    id: int
    created_at: datetime

    model_config = {"from_attributes": True}

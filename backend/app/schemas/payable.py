from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class PayablePaymentCreate(BaseModel):
    amount: Decimal = Field(gt=0)
    method: str = Field(default="dinheiro", min_length=2, max_length=30)
    notes: str | None = None


class PayableCreate(BaseModel):
    supplier_id: int | None = None
    stock_entry_id: int | None = None
    description: str = Field(min_length=2, max_length=220)
    document_number: str | None = Field(default=None, max_length=80)
    category: str | None = Field(default=None, max_length=80)
    original_amount: Decimal = Field(gt=0)
    due_date: datetime | None = None
    issue_date: datetime | None = None
    competence_date: datetime | None = None
    notes: str | None = None


class PayableUpdate(BaseModel):
    supplier_id: int | None = None
    stock_entry_id: int | None = None
    description: str | None = Field(default=None, min_length=2, max_length=220)
    document_number: str | None = Field(default=None, max_length=80)
    category: str | None = Field(default=None, max_length=80)
    due_date: datetime | None = None
    issue_date: datetime | None = None
    competence_date: datetime | None = None
    notes: str | None = None


class PayablePaymentRead(BaseModel):
    id: int
    payable_id: int
    user_id: int | None
    amount: Decimal
    method: str
    notes: str | None
    paid_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PayableRead(BaseModel):
    id: int
    number: str | None
    supplier_id: int | None
    supplier_name: str | None = None
    stock_entry_id: int | None
    stock_entry_number: str | None = None
    description: str
    document_number: str | None
    category: str | None
    original_amount: Decimal
    paid_amount: Decimal
    balance_amount: Decimal
    status: str
    issue_date: datetime | None
    due_date: datetime | None
    competence_date: datetime | None
    created_at: datetime
    settled_at: datetime | None
    notes: str | None
    payments: list[PayablePaymentRead] = []

    model_config = ConfigDict(from_attributes=True)

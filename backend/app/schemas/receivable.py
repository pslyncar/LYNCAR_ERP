from datetime import datetime
from decimal import Decimal

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ReceivablePaymentCreate(BaseModel):
    amount: Decimal = Field(gt=0)
    method: str = Field(default="dinheiro", min_length=2, max_length=30)
    notes: str | None = None


class ReceivableAccountPaymentCreate(ReceivablePaymentCreate):
    pass


class ReceivableManualCreate(BaseModel):
    client_id: int = Field(gt=0)
    description: str = Field(
        default="Lançamento manual de crediário",
        min_length=2,
        max_length=220,
    )
    amount: Decimal = Field(gt=0)
    due_date: datetime | None = None
    notes: str | None = None
    entry_type: Literal["legacy", "service"] = "legacy"


class ReceivablePaymentRead(BaseModel):
    id: int
    receivable_id: int
    user_id: int | None
    amount: Decimal
    method: str
    notes: str | None
    paid_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ReceivableSaleItemRead(BaseModel):
    id: int
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    total_price: Decimal


class ReceivableRead(BaseModel):
    id: int
    number: str | None
    sale_id: int | None
    client_id: int | None
    description: str
    original_amount: Decimal
    paid_amount: Decimal
    balance_amount: Decimal
    status: str
    due_date: datetime | None
    created_at: datetime
    settled_at: datetime | None
    notes: str | None
    entry_type: str = "legacy"
    fiscal_document_id: int | None = None
    fiscal_document_status: str | None = None
    fiscal_document_type: str | None = None
    fiscal_document_series: int | None = None
    fiscal_document_number: int | None = None
    client_name: str | None = None
    sale_number: str | None = None
    sale_sold_at: datetime | None = None
    sale_items: list[ReceivableSaleItemRead] = []
    payments: list[ReceivablePaymentRead] = []

    model_config = ConfigDict(from_attributes=True)

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

CashClosingStatus = Literal["pending_treasury", "approved", "divergent"]


class CashClosingPaymentCreate(BaseModel):
    method: str = Field(min_length=2, max_length=30)
    amount: Decimal = Field(ge=0)


class CashClosingMovementCreate(BaseModel):
    movement_type: str = Field(min_length=2, max_length=30)
    amount: Decimal = Field(gt=0)
    reason: str | None = Field(default=None, max_length=220)
    created_at: datetime | None = None
    authorized_by_operator_id: int | None = None
    authorized_by_operator_name: str | None = Field(default=None, max_length=150)


class CashClosingCreate(BaseModel):
    cash_session_id: int | None = None
    cash_register_number: str | None = Field(default=None, max_length=10)
    terminal_key: str | None = Field(default=None, max_length=180)
    operator_name: str | None = Field(default=None, max_length=150)
    opened_at: datetime | None = None
    opening_amount: Decimal = Field(default=0, ge=0)
    expected_cash_amount: Decimal = Field(default=0, ge=0)
    counted_cash_amount: Decimal = Field(default=0, ge=0)
    total_sales_amount: Decimal = Field(default=0, ge=0)
    total_sales_count: int = Field(default=0, ge=0)
    total_withdrawal_amount: Decimal = Field(default=0, ge=0)
    total_supply_amount: Decimal = Field(default=0, ge=0)
    authorized_by_operator_id: int | None = None
    authorized_by_operator_name: str | None = Field(default=None, max_length=150)
    notes: str | None = None
    payments: list[CashClosingPaymentCreate] = []
    movements: list[CashClosingMovementCreate] = []


class CashClosingTreasuryReview(BaseModel):
    status: CashClosingStatus
    notes: str | None = None
    counted_cash_amount: Decimal | None = Field(default=None, ge=0)


class CashClosingPaymentRead(CashClosingPaymentCreate):
    id: int

    model_config = ConfigDict(from_attributes=True)


class CashClosingMovementRead(CashClosingMovementCreate):
    id: int

    model_config = ConfigDict(from_attributes=True)


class CashClosingRead(BaseModel):
    id: int
    number: str | None
    cash_session_id: int | None
    cash_register_number: str | None
    operator_name: str | None
    opened_at: datetime | None
    closed_at: datetime
    business_date: date | None
    crossed_business_day: bool = False
    business_day_cutoff_minutes: int = 180
    opened_by_user_id: int | None
    closed_by_user_id: int | None
    opening_amount: Decimal
    expected_cash_amount: Decimal
    counted_cash_amount: Decimal
    cash_difference_amount: Decimal
    total_sales_amount: Decimal
    total_sales_count: int
    total_withdrawal_amount: Decimal
    total_supply_amount: Decimal
    authorized_by_operator_id: int | None
    authorized_by_operator_name: str | None
    status: CashClosingStatus
    treasury_checked_by_user_id: int | None
    treasury_checked_at: datetime | None
    treasury_notes: str | None
    notes: str | None
    payments: list[CashClosingPaymentRead] = []
    movements: list[CashClosingMovementRead] = []

    model_config = ConfigDict(from_attributes=True)

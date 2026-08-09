from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class CompanyBillingRead(BaseModel):
    id: int
    company_id: int
    company_code: str
    company_name: str
    reference_month: str
    due_date: date
    amount: Decimal
    payment_method: str | None
    status: str
    paid_at: datetime | None
    paid_amount: Decimal | None
    mercado_pago_payment_id: str | None = None
    mercado_pago_status: str | None = None
    pix_qr_code: str | None = None
    pix_qr_code_base64: str | None = None
    pix_ticket_url: str | None = None
    notes: str | None
    created_at: datetime


class CompanyBillingCreate(BaseModel):
    company_id: int
    reference_month: str = Field(pattern=r"^\d{4}-\d{2}$")
    due_date: date
    amount: Decimal = Field(gt=0)
    payment_method: str | None = Field(default=None, max_length=40)
    notes: str | None = None


class CompanyBillingUpdate(BaseModel):
    due_date: date | None = None
    amount: Decimal | None = Field(default=None, gt=0)
    payment_method: str | None = Field(default=None, max_length=40)
    status: str | None = Field(default=None, max_length=20)
    notes: str | None = None


class CompanyBillingPayment(BaseModel):
    paid_amount: Decimal | None = Field(default=None, gt=0)
    notes: str | None = None

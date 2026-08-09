from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

SaleStatus = Literal["rascunho", "finalizada", "cancelada"]
SaleSource = Literal["pdv", "venda", "os", "teste"]
PaymentMethod = Literal[
    "dinheiro",
    "pix",
    "debito",
    "credito",
    "boleto",
    "transferencia",
    "crediario",
    "outro",
]


class SaleItemCreate(BaseModel):
    product_id: int | None = None
    barcode: str | None = Field(default=None, max_length=80)
    description: str = Field(min_length=2, max_length=220)
    quantity: Decimal = Field(default=1, gt=0)
    unit_price: Decimal = Field(default=0, ge=0)
    discount_amount: Decimal = Field(default=0, ge=0)


class SalePaymentCreate(BaseModel):
    method: PaymentMethod
    amount: Decimal = Field(gt=0)
    authorization_code: str | None = Field(default=None, max_length=80)
    notes: str | None = None


class SaleCreate(BaseModel):
    client_id: int | None = None
    seller_user_id: int | None = None
    source: SaleSource = "pdv"
    cash_register_number: str | None = Field(default=None, max_length=10)
    cash_session_id: int | None = None
    status: SaleStatus = "finalizada"
    discount_amount: Decimal = Field(default=0, ge=0)
    consumer_cpf: str | None = Field(default=None, max_length=14)
    offline_client_id: str | None = Field(default=None, max_length=80)
    notes: str | None = None
    items: list[SaleItemCreate] = Field(min_length=1)
    payments: list[SalePaymentCreate] = Field(min_length=1)

    @model_validator(mode="after")
    def validate_finalized_payment(self) -> "SaleCreate":
        if self.status == "finalizada" and not self.payments:
            raise ValueError("Venda finalizada precisa ter pagamento.")
        return self


class SalePaymentsUpdate(BaseModel):
    payments: list[SalePaymentCreate] = Field(min_length=1)


class SalePaymentRead(SalePaymentCreate):
    id: int

    model_config = ConfigDict(from_attributes=True)


class SaleItemRead(BaseModel):
    id: int
    product_id: int | None
    barcode: str | None
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    discount_amount: Decimal
    total_price: Decimal

    model_config = ConfigDict(from_attributes=True)


class SaleRead(BaseModel):
    id: int
    number: str | None
    client_id: int | None
    seller_user_id: int | None
    seller_name: str | None = None
    cash_register_number: str | None
    cash_session_id: int | None
    source: SaleSource
    status: SaleStatus
    subtotal_amount: Decimal
    discount_amount: Decimal
    total_amount: Decimal
    amount_paid: Decimal
    change_amount: Decimal
    consumer_cpf: str | None
    offline_client_id: str | None = None
    notes: str | None
    sold_at: datetime
    canceled_at: datetime | None
    has_fiscal_document: bool = False
    has_authorized_fiscal_document: bool = False
    items: list[SaleItemRead] = []
    payments: list[SalePaymentRead] = []

    model_config = ConfigDict(from_attributes=True)


class SaleSellerRead(BaseModel):
    id: int
    name: str
    seller_code: str | None
    role: str

    model_config = ConfigDict(from_attributes=True)

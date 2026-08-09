from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

ContractType = Literal["avulso", "mensal"]
PersonType = Literal["PF", "PJ"]
CreditStatus = Literal["liberado", "em_analise", "bloqueado"]


class ClientBase(BaseModel):
    name: str = Field(min_length=2, max_length=180)
    person_type: PersonType = "PF"
    trade_name: str | None = Field(default=None, max_length=180)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    municipal_registration: str | None = Field(default=None, max_length=40)
    tax_contributor_type: str | None = Field(default=None, max_length=20)
    city_code: str | None = Field(default=None, max_length=20)
    country_code: str | None = Field(default=None, max_length=4)
    country_name: str | None = Field(default=None, max_length=80)
    suframa: str | None = Field(default=None, max_length=20)
    contact_person: str | None = Field(default=None, max_length=150)
    phone: str | None = Field(default=None, max_length=40)
    mobile_phone: str | None = Field(default=None, max_length=40)
    email: EmailStr | None = None
    secondary_email: EmailStr | None = None
    address: str | None = None
    address_number: str | None = Field(default=None, max_length=20)
    address_complement: str | None = Field(default=None, max_length=120)
    neighborhood: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, min_length=2, max_length=2)
    zip_code: str | None = Field(default=None, max_length=20)
    contract_type: ContractType = "avulso"
    monthly_fee: Decimal = Field(default=Decimal("0"), ge=0, max_digits=12, decimal_places=2)
    monthly_due_day: int | None = Field(default=None, ge=1, le=31)
    allow_credit: bool = False
    credit_limit: Decimal = Field(default=Decimal("0"), ge=0, max_digits=12, decimal_places=2)
    credit_status: CreditStatus = "liberado"
    payment_terms: str | None = Field(default=None, max_length=80)
    billing_notes: str | None = None
    notes: str | None = None
    active: bool = True


class ClientCreate(ClientBase):
    pass


class ClientUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=180)
    person_type: PersonType | None = None
    trade_name: str | None = Field(default=None, max_length=180)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    municipal_registration: str | None = Field(default=None, max_length=40)
    tax_contributor_type: str | None = Field(default=None, max_length=20)
    city_code: str | None = Field(default=None, max_length=20)
    country_code: str | None = Field(default=None, max_length=4)
    country_name: str | None = Field(default=None, max_length=80)
    suframa: str | None = Field(default=None, max_length=20)
    contact_person: str | None = Field(default=None, max_length=150)
    phone: str | None = Field(default=None, max_length=40)
    mobile_phone: str | None = Field(default=None, max_length=40)
    email: EmailStr | None = None
    secondary_email: EmailStr | None = None
    address: str | None = None
    address_number: str | None = Field(default=None, max_length=20)
    address_complement: str | None = Field(default=None, max_length=120)
    neighborhood: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, min_length=2, max_length=2)
    zip_code: str | None = Field(default=None, max_length=20)
    contract_type: ContractType | None = None
    monthly_fee: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    monthly_due_day: int | None = Field(default=None, ge=1, le=31)
    allow_credit: bool | None = None
    credit_limit: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    credit_status: CreditStatus | None = None
    payment_terms: str | None = Field(default=None, max_length=80)
    billing_notes: str | None = None
    notes: str | None = None
    active: bool | None = None


class ClientRead(ClientBase):
    id: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class AttendanceRulePayload(BaseModel):
    day_type: str = Field(max_length=20)
    attends: bool = True
    charges: bool = True
    multiplier: Decimal = Field(default=Decimal("1"), ge=0)
    notes: str | None = None


class AttendanceRuleRead(AttendanceRulePayload):
    id: int

    model_config = {"from_attributes": True}


class ContractConsumptionItemPayload(BaseModel):
    product_id: int = Field(gt=0)
    quantity_per_person: Decimal = Field(gt=0)
    unit: str = Field(default="un", max_length=20)
    waste_percent: Decimal = Field(default=Decimal("0"), ge=0)
    active: bool = True
    notes: str | None = None


class ContractConsumptionItemRead(ContractConsumptionItemPayload):
    id: int
    product_name: str | None = None

    model_config = {"from_attributes": True}


class ServiceContractCreate(BaseModel):
    client_id: int = Field(gt=0)
    description: str = Field(min_length=2, max_length=180)
    value_per_person: Decimal = Field(gt=0)
    default_people_quantity: Decimal = Field(gt=0)
    billing_periodicity: str = Field(default="quinzenal", max_length=20)
    start_date: date
    status: str = Field(default="active", max_length=30)
    active: bool = True
    notes: str | None = None
    rules: list[AttendanceRulePayload] = Field(default_factory=list)
    consumption_items: list[ContractConsumptionItemPayload] = Field(default_factory=list)


class ServiceContractUpdate(BaseModel):
    client_id: int | None = Field(default=None, gt=0)
    description: str | None = Field(default=None, min_length=2, max_length=180)
    value_per_person: Decimal | None = Field(default=None, gt=0)
    default_people_quantity: Decimal | None = Field(default=None, gt=0)
    billing_periodicity: str | None = Field(default=None, max_length=20)
    start_date: date | None = None
    status: str | None = Field(default=None, max_length=30)
    active: bool | None = None
    notes: str | None = None
    rules: list[AttendanceRulePayload] | None = None
    consumption_items: list[ContractConsumptionItemPayload] | None = None


class ServiceContractRead(BaseModel):
    id: int
    number: str | None
    client_id: int
    client_name: str | None = None
    description: str
    value_per_person: Decimal
    default_people_quantity: Decimal
    billing_periodicity: str
    start_date: date
    status: str
    active: bool
    notes: str | None
    created_at: datetime
    updated_at: datetime
    rules: list[AttendanceRuleRead] = []
    consumption_items: list[ContractConsumptionItemRead] = []

    model_config = {"from_attributes": True}


class AppointmentConsumptionItemPayload(BaseModel):
    id: int | None = None
    product_id: int = Field(gt=0)
    quantity_planned: Decimal = Field(default=Decimal("0"), ge=0)
    quantity_confirmed: Decimal = Field(default=Decimal("0"), ge=0)
    unit: str = Field(default="un", max_length=20)
    notes: str | None = None


class AppointmentConsumptionItemRead(AppointmentConsumptionItemPayload):
    id: int
    product_name: str | None = None
    unit_cost: Decimal | None = None
    total_cost: Decimal | None = None
    stock_movement_id: int | None = None

    model_config = {"from_attributes": True}


class ServiceAppointmentUpdate(BaseModel):
    appointment_date: date | None = None
    day_type: str | None = Field(default=None, max_length=20)
    people_quantity: Decimal | None = Field(default=None, ge=0)
    value_per_person: Decimal | None = Field(default=None, ge=0)
    multiplier: Decimal | None = Field(default=None, ge=0)
    status: str | None = Field(default=None, max_length=30)
    notes: str | None = None
    items: list[AppointmentConsumptionItemPayload] | None = None


class ServiceAppointmentRead(BaseModel):
    id: int
    contract_id: int
    contract_number: str | None = None
    client_name: str | None = None
    appointment_date: date
    day_type: str
    people_quantity: Decimal
    value_per_person: Decimal
    multiplier: Decimal
    total_amount: Decimal
    status: str
    stock_posted: bool
    stock_posted_at: datetime | None
    confirmed_at: datetime | None
    notes: str | None
    items: list[AppointmentConsumptionItemRead] = []

    model_config = {"from_attributes": True}


class GenerateAppointmentsPayload(BaseModel):
    period_start: date
    period_end: date


class ServiceBillingCreate(BaseModel):
    period_start: date
    period_end: date
    due_date: date | None = None
    notes: str | None = None


class ServiceBillingItemRead(BaseModel):
    id: int
    appointment_id: int | None
    item_date: date
    description: str
    people_quantity: Decimal
    unit_price: Decimal
    multiplier: Decimal
    total_amount: Decimal

    model_config = {"from_attributes": True}


class ServiceBillingRead(BaseModel):
    id: int
    number: str | None
    contract_id: int
    receivable_id: int | None
    period_start: date
    period_end: date
    total_amount: Decimal
    status: str
    generated_at: datetime
    notes: str | None
    items: list[ServiceBillingItemRead] = []

    model_config = {"from_attributes": True}

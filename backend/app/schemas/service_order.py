from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

ServiceOrderStatus = Literal[
    "aberta",
    "em_diagnostico",
    "aguardando_aprovacao",
    "aguardando_retorno_cliente",
    "aguardando_retirada",
    "em_execucao",
    "concluida",
    "cancelada",
]
ServiceOrderPriority = Literal["baixa", "media", "alta"]


class ServiceOrderBase(BaseModel):
    client_id: int
    equipment_id: int | None = None
    ticket_id: int | None = None
    assigned_user_id: int | None = None
    number: str | None = Field(default=None, max_length=40)
    title: str = Field(min_length=3, max_length=180)
    status: ServiceOrderStatus = "aberta"
    priority: ServiceOrderPriority = "media"
    service_type: str | None = Field(default=None, max_length=80)
    received_equipment: str | None = Field(default=None, max_length=180)
    waiting_reason: str | None = Field(default=None, max_length=220)
    request_description: str = Field(min_length=3)
    technical_diagnosis: str | None = None
    service_performed: str | None = None
    internal_notes: str | None = None
    labor_amount: Decimal = Field(default=0, ge=0)
    discount_amount: Decimal = Field(default=0, ge=0)
    scheduled_at: datetime | None = None


class ServiceOrderCreate(ServiceOrderBase):
    pass


class ServiceOrderUpdate(BaseModel):
    client_id: int | None = None
    equipment_id: int | None = None
    ticket_id: int | None = None
    assigned_user_id: int | None = None
    number: str | None = Field(default=None, max_length=40)
    title: str | None = Field(default=None, min_length=3, max_length=180)
    status: ServiceOrderStatus | None = None
    priority: ServiceOrderPriority | None = None
    service_type: str | None = Field(default=None, max_length=80)
    received_equipment: str | None = Field(default=None, max_length=180)
    waiting_reason: str | None = Field(default=None, max_length=220)
    request_description: str | None = Field(default=None, min_length=3)
    technical_diagnosis: str | None = None
    service_performed: str | None = None
    internal_notes: str | None = None
    labor_amount: Decimal | None = Field(default=None, ge=0)
    discount_amount: Decimal | None = Field(default=None, ge=0)
    scheduled_at: datetime | None = None


class ServiceOrderItemCreate(BaseModel):
    product_id: int | None = None
    description: str = Field(min_length=2, max_length=180)
    quantity: Decimal = Field(default=1, gt=0)
    unit_price: Decimal = Field(default=0, ge=0)


class ServiceOrderItemRead(ServiceOrderItemCreate):
    id: int
    service_order_id: int
    total_price: Decimal
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ServiceOrderRead(ServiceOrderBase):
    id: int
    opened_by_user_id: int | None = None
    opened_by_user_name: str | None = None
    opened_by_user_code: str | None = None
    sold_by_user_id: int | None = None
    sold_by_user_name: str | None = None
    sold_by_user_code: str | None = None
    assigned_user_name: str | None = None
    assigned_user_code: str | None = None
    items_amount: Decimal
    total_amount: Decimal
    opened_at: datetime
    closed_at: datetime | None
    created_at: datetime
    items: list[ServiceOrderItemRead] = []
    events: list["ServiceOrderEventRead"] = []

    model_config = ConfigDict(from_attributes=True)


class ServiceOrderWorkflowAction(BaseModel):
    notes: str | None = Field(default=None, max_length=500)


class ServiceOrderEventRead(BaseModel):
    id: int
    service_order_id: int
    user_id: int | None
    user_name: str | None = None
    event_type: str
    status_from: str | None
    status_to: str | None
    assigned_user_id: int | None
    assigned_user_name: str | None = None
    assigned_user_code: str | None = None
    notes: str | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

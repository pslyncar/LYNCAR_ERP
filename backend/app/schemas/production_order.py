from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ProductionOrderCreate(BaseModel):
    product_id: int
    quantity: Decimal = Field(gt=0)
    due_date: date | None = None
    notes: str | None = None


class ProductionOrderComplete(BaseModel):
    produced_quantity: Decimal | None = Field(default=None, gt=0)
    notes: str | None = None


class ProductionOrderCancel(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


class ProductionOrderComponentRead(BaseModel):
    id: int
    component_product_id: int
    component_name: str
    quantity: Decimal
    unit: str
    waste_percent: Decimal
    unit_cost: Decimal | None = None
    total_cost: Decimal | None = None

    model_config = ConfigDict(from_attributes=True)


class ProductionOrderComponentPreview(BaseModel):
    component_product_id: int
    component_name: str
    requested_quantity: Decimal
    requested_unit: str
    required_quantity: Decimal
    stock_quantity: Decimal
    unit: str
    waste_percent: Decimal
    unit_cost: Decimal | None = None
    total_cost: Decimal | None = None
    enough_stock: bool


class ProductionOrderPreview(BaseModel):
    product_id: int
    quantity: Decimal
    unit: str
    estimated_unit_cost: Decimal | None = None
    estimated_total_cost: Decimal | None = None
    components: list[ProductionOrderComponentPreview]


class ProductionOrderRead(BaseModel):
    id: int
    number: str | None
    product_id: int
    product_name: str
    user_id: int | None
    completed_by_user_id: int | None = None
    canceled_by_user_id: int | None = None
    status: str
    quantity: Decimal
    produced_quantity: Decimal
    unit: str
    unit_cost: Decimal | None = None
    total_cost: Decimal | None = None
    estimated_unit_cost: Decimal | None = None
    estimated_total_cost: Decimal | None = None
    due_date: date | None = None
    notes: str | None = None
    cancellation_reason: str | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    canceled_at: datetime | None = None
    produced_at: datetime
    components: list[ProductionOrderComponentRead] = []

    model_config = ConfigDict(from_attributes=True)

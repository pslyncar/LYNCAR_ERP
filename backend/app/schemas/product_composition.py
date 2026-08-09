from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ProductCompositionItemCreate(BaseModel):
    component_product_id: int
    quantity: Decimal = Field(gt=0)
    unit: str = Field(default="un", max_length=20)
    waste_percent: Decimal = Field(default=0, ge=0)
    notes: str | None = None


class ProductCompositionItemUpdate(BaseModel):
    quantity: Decimal | None = Field(default=None, gt=0)
    unit: str | None = Field(default=None, max_length=20)
    waste_percent: Decimal | None = Field(default=None, ge=0)
    notes: str | None = None


class ProductCompositionItemRead(BaseModel):
    id: int
    product_id: int
    component_product_id: int
    component_name: str
    component_internal_code: str | None = None
    component_unit: str
    component_unit_cost: Decimal | None = None
    quantity: Decimal
    unit: str
    waste_percent: Decimal
    notes: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

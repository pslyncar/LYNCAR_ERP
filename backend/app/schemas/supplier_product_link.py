from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class SupplierProductLinkRead(BaseModel):
    id: int
    supplier_id: int
    supplier_name: str
    product_id: int
    product_name: str
    product_internal_code: str | None = None
    supplier_product_code: str
    supplier_description: str | None = None
    commercial_gtin: str | None = None
    tax_gtin: str | None = None
    supplier_unit: str | None = None
    stock_unit: str | None = None
    conversion_factor: Decimal | None = None
    last_cost: Decimal | None = None
    last_seen_at: datetime | None = None
    active: bool = True

    model_config = ConfigDict(from_attributes=True)


class SupplierProductLinkUpdate(BaseModel):
    supplier_product_code: str | None = Field(default=None, min_length=1, max_length=80)
    supplier_description: str | None = Field(default=None, max_length=220)
    commercial_gtin: str | None = Field(default=None, max_length=80)
    tax_gtin: str | None = Field(default=None, max_length=80)
    supplier_unit: str | None = Field(default=None, max_length=20)
    stock_unit: str | None = Field(default=None, max_length=20)
    conversion_factor: Decimal | None = Field(default=None, gt=0)
    active: bool | None = None

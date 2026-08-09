from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class ProductBatchRead(BaseModel):
    id: int
    product_id: int
    batch_number: str | None = None
    expiration_date: date | None = None
    quantity: Decimal
    unit: str
    source_type: str | None = None
    source_id: int | None = None
    source_number: str | None = None
    supplier_name: str | None = None
    invoice_number: str | None = None
    invoice_series: str | None = None
    notes: str | None = None
    active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

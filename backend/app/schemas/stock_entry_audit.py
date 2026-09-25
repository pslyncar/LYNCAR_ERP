from datetime import datetime

from pydantic import BaseModel, ConfigDict


class StockEntryAuditEventRead(BaseModel):
    id: int
    stock_entry_id: int
    stock_entry_item_id: int | None = None
    user_id: int | None = None
    user_name: str | None = None
    action: str
    source: str
    reason: str | None = None
    old_value: str | None = None
    new_value: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

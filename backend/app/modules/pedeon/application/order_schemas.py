from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class OrderItemRead(BaseModel):
    product_id: int | None
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    total: Decimal
    customer_notes: str | None = None
    station_code: str | None = None
    station_name: str | None = None
    modifiers: list["OrderItemModifierRead"] = Field(default_factory=list)


class OrderItemModifierRead(BaseModel):
    group_name: str
    option_name: str
    quantity: Decimal
    unit_price: Decimal
    total: Decimal


class OrderSummaryRead(BaseModel):
    id: int
    public_id: str
    display_number: str
    source_channel: str
    external_order_id: str | None = None
    status: str
    payment_status: str
    fulfillment_type: str
    customer_name: str
    customer_phone: str
    total: Decimal
    created_at: datetime


class OrderDetailRead(OrderSummaryRead):
    customer_email: str | None = None
    customer_document: str | None = None
    delivery_address: dict | None = None
    customer_notes: str | None = None
    subtotal: Decimal
    discount: Decimal
    delivery_fee: Decimal
    payment_method: str | None = None
    local_payment_method: str | None = None
    cash_change_for: str | None = None
    source_metadata: dict = Field(default_factory=dict)
    accepted_at: datetime | None = None
    preparation_started_at: datetime | None = None
    ready_at: datetime | None = None
    out_for_delivery_at: datetime | None = None
    completed_at: datetime | None = None
    items: list[OrderItemRead]


class OrderPageRead(BaseModel):
    items: list[OrderSummaryRead]
    page: int
    page_size: int
    total: int
    total_pages: int


class OrderStatusUpdate(BaseModel):
    status: str = Field(min_length=3, max_length=40)


class TerminalFeedEventRead(BaseModel):
    cursor: int
    event_key: str
    event_type: str
    order_id: str
    payload: dict = Field(default_factory=dict)
    created_at: datetime


class TerminalFeedRead(BaseModel):
    terminal_id: int
    next_cursor: int
    has_more: bool
    events: list[TerminalFeedEventRead] = Field(default_factory=list)


class TerminalPrintJobRead(BaseModel):
    id: int
    job_key: str
    document_type: str
    payload: dict = Field(default_factory=dict)
    attempts: int
    created_at: datetime


class TerminalPrintJobResult(BaseModel):
    status: str = Field(pattern=r"^(printed|failed)$")
    error: str | None = Field(default=None, max_length=1000)

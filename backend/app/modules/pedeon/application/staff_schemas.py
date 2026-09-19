from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field

from app.modules.pedeon.application.public_schemas import CartQuoteItem


class EdgeStaffOrderCreate(BaseModel):
    edge_node_key: str = Field(min_length=16, max_length=80)
    edge_terminal_key: str = Field(min_length=16, max_length=180)
    terminal_id: int = Field(ge=1)
    idempotency_key: str = Field(min_length=16, max_length=100)
    source_channel: Literal["onsite_waiter", "pdv_counter"] = "onsite_waiter"
    table_label: str | None = Field(default=None, max_length=80)
    command_label: str | None = Field(default=None, max_length=80)
    customer_name: str = Field(default="Consumidor no local", min_length=2, max_length=180)
    customer_notes: str | None = Field(default=None, max_length=1000)
    waiter_email: str | None = Field(default=None, max_length=254)
    waiter_name: str | None = Field(default=None, max_length=150)
    items: list[CartQuoteItem] = Field(min_length=1, max_length=100)


class EdgeOrderCheckout(BaseModel):
    edge_node_key: str = Field(min_length=16, max_length=80)
    edge_terminal_key: str = Field(min_length=16, max_length=180)
    terminal_id: int = Field(ge=1)
    idempotency_key: str = Field(min_length=16, max_length=120)
    payment_method: Literal["dinheiro", "pix", "debito", "credito"]
    amount_paid: Decimal = Field(gt=0)
    authorization_code: str | None = Field(default=None, max_length=80)
    operator_name: str = Field(min_length=2, max_length=150)
    operator_id: int = Field(ge=0)
    operator_type: Literal["pedeon_operator", "erp_owner"] = "pedeon_operator"
    cash_register_number: str | None = Field(default=None, max_length=10)
    cash_session_id: int = Field(ge=1)
    cash_session_local_key: str = Field(min_length=16, max_length=120)


class EdgeCashSessionOpen(BaseModel):
    edge_node_key: str = Field(min_length=16, max_length=80)
    edge_terminal_key: str = Field(min_length=16, max_length=180)
    terminal_id: int = Field(ge=1)
    local_key: str = Field(min_length=16, max_length=120)
    cash_register_number: str = Field(min_length=1, max_length=10)
    operator_id: int = Field(ge=0)
    operator_type: Literal["pedeon_operator", "erp_owner"] = "pedeon_operator"
    operator_name: str = Field(min_length=2, max_length=150)
    opening_amount: Decimal = Field(default=0, ge=0)

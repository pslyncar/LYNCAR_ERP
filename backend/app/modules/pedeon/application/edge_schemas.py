from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


EDGE_PROTOCOL_VERSION = 1
EDGE_CAPABILITIES = (
    "catalog_cache",
    "customer_cache",
    "order_relay",
    "local_printing",
    "lan_coordination",
    "durable_outbox",
)


class EdgeRegisterRequest(BaseModel):
    terminal_key: str = Field(min_length=16, max_length=180)
    node_key: str = Field(min_length=16, max_length=80)
    device_label: str | None = Field(default=None, max_length=120)
    device_role: Literal["kitchen", "cashier", "dining_room"] = "cashier"
    app_version: str | None = Field(default=None, max_length=40)
    protocol_version: int = Field(default=EDGE_PROTOCOL_VERSION, ge=1)


class EdgeHeartbeatRequest(BaseModel):
    terminal_key: str = Field(min_length=16, max_length=180)
    cursors: dict[str, int] = Field(default_factory=dict)
    last_error: str | None = Field(default=None, max_length=1000)

    @field_validator("cursors")
    @classmethod
    def validate_cursors(cls, value: dict[str, int]) -> dict[str, int]:
        allowed = {"catalog", "orders", "outbox"}
        if set(value) - allowed:
            raise ValueError("Cursor de sincronização desconhecido.")
        if any(cursor < 0 for cursor in value.values()):
            raise ValueError("Cursores de sincronização não podem ser negativos.")
        return value


class EdgeNodeRead(BaseModel):
    node_key: str
    store_id: int
    public_slug: str
    terminal_id: int
    status: str
    protocol_version: int
    capabilities: list[str]
    cursors: dict[str, int]
    app_version: str | None = None
    device_label: str | None = None
    registered_at: datetime
    last_seen_at: datetime
    server_time: datetime


class EdgeTerminalAuthorizeRequest(BaseModel):
    edge_node_key: str = Field(min_length=16, max_length=80)
    edge_terminal_key: str = Field(min_length=16, max_length=180)
    terminal_key: str = Field(min_length=16, max_length=180)


class EdgeTerminalAuthorizationRead(BaseModel):
    terminal_id: int
    device_label: str | None = None
    capabilities: list[str]
    station_ids: list[int]
    notification_mode: str
    priority: int

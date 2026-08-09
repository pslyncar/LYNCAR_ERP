from pydantic import BaseModel


class DashboardAlertRead(BaseModel):
    equipment_id: int
    hostname: str
    client_id: int
    client_name: str
    type: str
    severity: str
    message: str


class DashboardContentRead(BaseModel):
    id: int
    content_type: str
    title: str
    description: str | None = None
    badge: str | None = None
    price_label: str | None = None
    image_url: str | None = None
    target_url: str | None = None
    button_label: str | None = None
    segment: str | None = None
    sort_order: int


class DashboardSummaryRead(BaseModel):
    dashboard_kind: str
    business_type: str | None = None
    has_fiscal_certificate: bool = False
    total_clients: int
    total_equipments: int
    online_equipments: int
    offline_equipments: int
    open_tickets: int
    in_progress_tickets: int
    completed_tickets: int
    canceled_tickets: int
    alerts: list[DashboardAlertRead]
    contents: list[DashboardContentRead] = []

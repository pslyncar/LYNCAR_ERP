from datetime import datetime

from pydantic import BaseModel, Field


class DashboardContentBase(BaseModel):
    content_type: str = Field(default="notice", max_length=30)
    title: str = Field(min_length=2, max_length=180)
    description: str | None = None
    badge: str | None = Field(default=None, max_length=80)
    price_label: str | None = Field(default=None, max_length=80)
    image_url: str | None = None
    target_url: str | None = None
    button_label: str | None = Field(default=None, max_length=80)
    segment: str | None = Field(default=None, max_length=60)
    sort_order: int = 0
    active: bool = True


class DashboardContentCreate(DashboardContentBase):
    pass


class DashboardContentUpdate(BaseModel):
    content_type: str | None = Field(default=None, max_length=30)
    title: str | None = Field(default=None, min_length=2, max_length=180)
    description: str | None = None
    badge: str | None = Field(default=None, max_length=80)
    price_label: str | None = Field(default=None, max_length=80)
    image_url: str | None = None
    target_url: str | None = None
    button_label: str | None = Field(default=None, max_length=80)
    segment: str | None = Field(default=None, max_length=60)
    sort_order: int | None = None
    active: bool | None = None


class DashboardContentRead(DashboardContentBase):
    id: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}

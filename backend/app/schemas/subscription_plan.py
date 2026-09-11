from decimal import Decimal

from pydantic import BaseModel, Field


class SubscriptionPlanRead(BaseModel):
    id: int
    code: str
    name: str
    monthly_price: str | None
    annual_price: str | None
    max_users: int | None
    max_pdv_terminals: int | None
    database_limit_mb: int
    file_limit_mb: int
    multi_company_limit: int | None
    marketplace_listing_limit: int | None
    api_enabled: bool
    priority_support: bool
    late_charges_enabled: bool
    late_fee_percent: Decimal
    late_interest_daily_percent: Decimal
    late_grace_days: int
    default_modules: list[str] = []
    active: bool
    sort_order: int

    model_config = {"from_attributes": True}


class SubscriptionPlanUpdate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    monthly_price: str | None = Field(default=None, max_length=30)
    annual_price: str | None = Field(default=None, max_length=30)
    max_users: int | None = Field(default=None, ge=1)
    max_pdv_terminals: int | None = Field(default=None, ge=1)
    database_limit_mb: int = Field(ge=1)
    file_limit_mb: int = Field(ge=1)
    multi_company_limit: int | None = Field(default=None, ge=1)
    marketplace_listing_limit: int | None = Field(default=None, ge=0)
    api_enabled: bool
    priority_support: bool
    late_charges_enabled: bool = False
    late_fee_percent: Decimal = Field(default=Decimal("0"), ge=0, le=100)
    late_interest_daily_percent: Decimal = Field(default=Decimal("0"), ge=0, le=100)
    late_grace_days: int = Field(default=0, ge=0, le=3650)
    default_modules: list[str] = []
    active: bool = True
    sort_order: int = 0


class SubscriptionPlanCreate(SubscriptionPlanUpdate):
    code: str = Field(min_length=2, max_length=40)

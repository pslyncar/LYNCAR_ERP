from sqlalchemy import Boolean, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class SubscriptionPlan(MasterBase):
    __tablename__ = "subscription_plans"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(80))
    monthly_price: Mapped[str | None] = mapped_column(String(30))
    annual_price: Mapped[str | None] = mapped_column(String(30))
    max_users: Mapped[int | None] = mapped_column(Integer)
    database_limit_mb: Mapped[int] = mapped_column(Integer)
    file_limit_mb: Mapped[int] = mapped_column(Integer)
    multi_company_limit: Mapped[int | None] = mapped_column(Integer)
    marketplace_listing_limit: Mapped[int | None] = mapped_column(Integer)
    api_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    priority_support: Mapped[bool] = mapped_column(Boolean, default=False)
    default_modules: Mapped[list[str]] = mapped_column(JSON, default=list)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

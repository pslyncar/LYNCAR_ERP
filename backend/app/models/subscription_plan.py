from decimal import Decimal

from sqlalchemy import Boolean, Integer, JSON, Numeric, String
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
    max_pdv_terminals: Mapped[int | None] = mapped_column(Integer)
    database_limit_mb: Mapped[int] = mapped_column(Integer)
    file_limit_mb: Mapped[int] = mapped_column(Integer)
    multi_company_limit: Mapped[int | None] = mapped_column(Integer)
    marketplace_listing_limit: Mapped[int | None] = mapped_column(Integer)
    api_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    priority_support: Mapped[bool] = mapped_column(Boolean, default=False)
    # Late-payment policy is owned by the plan. A disabled policy means that
    # companies on the plan never receive grace-period, fee, or interest rules
    # from the global Master finance settings.
    late_charges_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    late_fee_percent: Mapped[Decimal] = mapped_column(
        Numeric(5, 2), default=Decimal("0"), nullable=False
    )
    late_interest_daily_percent: Mapped[Decimal] = mapped_column(
        Numeric(7, 4), default=Decimal("0"), nullable=False
    )
    late_grace_days: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    default_modules: Mapped[list[str]] = mapped_column(JSON, default=list)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

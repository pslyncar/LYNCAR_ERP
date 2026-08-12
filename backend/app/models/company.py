from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Boolean, Date, DateTime, Integer, JSON, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class Company(MasterBase):
    __tablename__ = "companies"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(180))
    business_type: Mapped[str] = mapped_column(String(60), default="custom")
    person_type: Mapped[str] = mapped_column(String(2), default="PF")
    document_number: Mapped[str | None] = mapped_column(String(30), index=True)
    state_registration: Mapped[str | None] = mapped_column(String(40))
    municipal_registration: Mapped[str | None] = mapped_column(String(40))
    trade_name: Mapped[str | None] = mapped_column(String(180))
    contact_name: Mapped[str | None] = mapped_column(String(150))
    responsible_cpf: Mapped[str | None] = mapped_column(String(14), index=True)
    responsible_birth_date: Mapped[date | None] = mapped_column(Date)
    phone: Mapped[str | None] = mapped_column(String(40))
    email: Mapped[str | None] = mapped_column(String(180))
    address_line: Mapped[str | None] = mapped_column(String(180))
    address_number: Mapped[str | None] = mapped_column(String(20))
    neighborhood: Mapped[str | None] = mapped_column(String(120))
    city: Mapped[str | None] = mapped_column(String(120))
    city_code: Mapped[str | None] = mapped_column(String(20))
    state: Mapped[str | None] = mapped_column(String(2))
    zip_code: Mapped[str | None] = mapped_column(String(20))
    tax_regime: Mapped[str | None] = mapped_column(String(40))
    crt: Mapped[str | None] = mapped_column(String(10))
    tax_regime_source: Mapped[str | None] = mapped_column(String(80))
    tax_regime_checked_at: Mapped[str | None] = mapped_column(String(30))
    cnpj_lookup_status: Mapped[str | None] = mapped_column(String(40))
    cnpj_lookup_message: Mapped[str | None] = mapped_column(Text)
    cnae_main: Mapped[str | None] = mapped_column(String(20))
    legal_nature: Mapped[str | None] = mapped_column(String(120))
    company_size: Mapped[str | None] = mapped_column(String(80))
    database_url: Mapped[str] = mapped_column(Text)
    plan: Mapped[str] = mapped_column(String(80), default="erp")
    plan_overrides: Mapped[dict | None] = mapped_column(JSON)
    enabled_modules: Mapped[list[str]] = mapped_column(JSON, default=list)
    monthly_price: Mapped[str | None] = mapped_column(String(30))
    billing_day: Mapped[str | None] = mapped_column(String(2))
    payment_method: Mapped[str | None] = mapped_column(String(40))
    contract_signed_at: Mapped[date | None] = mapped_column(Date)
    contract_expires_at: Mapped[date | None] = mapped_column(Date)
    contract_file_url: Mapped[str | None] = mapped_column(Text)
    contract_file_name: Mapped[str | None] = mapped_column(String(220))
    contract_notes: Mapped[str | None] = mapped_column(Text)
    business_day_cutoff_minutes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=180,
    )
    sales_max_discount_percent: Mapped[Decimal] = mapped_column(
        Numeric(5, 2),
        nullable=False,
        default=Decimal("100.00"),
    )
    digital_certificate_configured: Mapped[bool] = mapped_column(Boolean, default=False)
    digital_certificate_name: Mapped[str | None] = mapped_column(String(180))
    digital_certificate_expires_at: Mapped[str | None] = mapped_column(String(30))
    digital_certificate_notes: Mapped[str | None] = mapped_column(Text)
    xml_email_token: Mapped[str | None] = mapped_column(String(40), unique=True, index=True)
    xml_email_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[str] = mapped_column(String(30), default="active")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

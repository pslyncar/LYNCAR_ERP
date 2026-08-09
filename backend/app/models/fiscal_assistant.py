from datetime import datetime
from decimal import Decimal

from sqlalchemy import Boolean, DateTime, Integer, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class FiscalSuggestion(Base):
    __tablename__ = "fiscal_suggestions"
    __table_args__ = (
        UniqueConstraint(
            "normalized_description",
            "barcode",
            "ncm",
            "cfop",
            "cst",
            "csosn",
            "ibs_cbs_cst",
            "selective_tax_cst",
            name="uq_fiscal_suggestion_signature",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    normalized_description: Mapped[str] = mapped_column(String(220), nullable=False, index=True)
    original_description: Mapped[str | None] = mapped_column(String(220))
    barcode: Mapped[str | None] = mapped_column(String(80), index=True)
    unit: Mapped[str | None] = mapped_column(String(20))
    ncm: Mapped[str | None] = mapped_column(String(20), index=True)
    cest: Mapped[str | None] = mapped_column(String(20))
    cfop: Mapped[str | None] = mapped_column(String(10))
    origin: Mapped[str | None] = mapped_column(String(2))
    cst: Mapped[str | None] = mapped_column(String(10))
    csosn: Mapped[str | None] = mapped_column(String(10))
    icms_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    pis_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    cofins_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ipi_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_cbs_cst: Mapped[str | None] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[str | None] = mapped_column(String(20))
    cbs_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_state_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    ibs_city_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    selective_tax_cst: Mapped[str | None] = mapped_column(String(10))
    selective_tax_classification: Mapped[str | None] = mapped_column(String(20))
    selective_tax_rate: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    source: Mapped[str] = mapped_column(String(40), nullable=False, default="internal")
    source_reference: Mapped[str | None] = mapped_column(String(120))
    usage_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    last_used_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    notes: Mapped[str | None] = mapped_column(Text)


class FiscalStateRule(Base):
    __tablename__ = "fiscal_state_rules"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    uf: Mapped[str] = mapped_column(String(2), nullable=False, index=True)
    rule_type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    ncm: Mapped[str | None] = mapped_column(String(20), index=True)
    cest: Mapped[str | None] = mapped_column(String(20), index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    legal_reference: Mapped[str | None] = mapped_column(Text)
    valid_from: Mapped[str | None] = mapped_column(String(20))
    valid_to: Mapped[str | None] = mapped_column(String(20))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(120), nullable=False, default="state_manual")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

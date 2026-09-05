from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class MasterFiscalReferenceSync(MasterBase):
    __tablename__ = "fiscal_reference_syncs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    source_type: Mapped[str] = mapped_column(String(30), nullable=False, unique=True, index=True)
    source_name: Mapped[str] = mapped_column(String(120), nullable=False)
    source_url: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending")
    records_loaded: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    message: Mapped[str | None] = mapped_column(Text)
    synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MasterFiscalNcmCode(MasterBase):
    __tablename__ = "fiscal_ncm_codes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False, unique=True, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_description: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    start_date: Mapped[str | None] = mapped_column(String(20))
    end_date: Mapped[str | None] = mapped_column(String(20))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(80), nullable=False, default="siscomex_classif")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MasterFiscalCfopCode(MasterBase):
    __tablename__ = "fiscal_cfop_codes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    code: Mapped[str] = mapped_column(String(10), nullable=False, unique=True, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    operation_type: Mapped[str | None] = mapped_column(String(40))
    direction: Mapped[str | None] = mapped_column(String(20))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(80), nullable=False, default="confaz_sinief")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MasterFiscalCestCode(MasterBase):
    __tablename__ = "fiscal_cest_codes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    cest: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    ncm: Mapped[str | None] = mapped_column(String(20), index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    segment: Mapped[str | None] = mapped_column(String(120))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(80), nullable=False, default="confaz_cest")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MasterIbsCbsClassTrib(MasterBase):
    __tablename__ = "fiscal_ibs_cbs_class_trib"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    cst: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    cst_description: Mapped[str | None] = mapped_column(Text)
    cclass_trib: Mapped[str] = mapped_column(String(20), nullable=False, unique=True, index=True)
    name: Mapped[str | None] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    group_type: Mapped[str | None] = mapped_column(String(40))
    requires_gibscbs: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    requires_rate_reduction: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    ibs_rate_reduction_percent: Mapped[float | None] = mapped_column()
    cbs_rate_reduction_percent: Mapped[float | None] = mapped_column()
    allows_credit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(80), nullable=False, default="portal_nfe_it_2025_002")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MasterFiscalCollectiveSuggestion(MasterBase):
    """Aggregated fiscal classifications confirmed by more than one company.

    The master database never stores a company name, document number, product
    identifier or the original XML here.  It only keeps a normalized product
    description and an aggregate classification that can be offered as an
    operator-confirmed suggestion.
    """

    __tablename__ = "fiscal_collective_suggestions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    signature: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    normalized_description: Mapped[str] = mapped_column(String(220), nullable=False, index=True)
    barcode: Mapped[str | None] = mapped_column(String(80), index=True)
    unit: Mapped[str | None] = mapped_column(String(20))
    ncm: Mapped[str | None] = mapped_column(String(20), index=True)
    cest: Mapped[str | None] = mapped_column(String(20))
    cfop: Mapped[str | None] = mapped_column(String(10))
    origin: Mapped[str | None] = mapped_column(String(2))
    cst: Mapped[str | None] = mapped_column(String(10))
    csosn: Mapped[str | None] = mapped_column(String(10))
    ibs_cbs_cst: Mapped[str | None] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[str | None] = mapped_column(String(20))
    selective_tax_cst: Mapped[str | None] = mapped_column(String(10))
    selective_tax_classification: Mapped[str | None] = mapped_column(String(20))
    confirmations_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    companies_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class MasterFiscalCollectiveObservation(MasterBase):
    """Anonymous per-company observation used only to count distinct companies."""

    __tablename__ = "fiscal_collective_observations"
    __table_args__ = (
        UniqueConstraint(
            "suggestion_signature",
            "company_fingerprint",
            name="uq_fiscal_collective_observation_company",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    suggestion_signature: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    company_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    confirmations_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    first_confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

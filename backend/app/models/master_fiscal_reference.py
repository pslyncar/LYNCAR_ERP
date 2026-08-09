from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
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
    allows_credit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(80), nullable=False, default="portal_nfe_it_2025_002")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

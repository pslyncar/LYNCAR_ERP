from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, LargeBinary, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class CompanyFiscalSetting(Base):
    __tablename__ = "company_fiscal_settings"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    legal_name: Mapped[Optional[str]] = mapped_column(String(180))
    trade_name: Mapped[Optional[str]] = mapped_column(String(180))
    cnpj: Mapped[Optional[str]] = mapped_column(String(20), index=True)
    state_registration: Mapped[Optional[str]] = mapped_column(String(40))
    municipal_registration: Mapped[Optional[str]] = mapped_column(String(40))
    crt: Mapped[Optional[str]] = mapped_column(String(10))
    tax_regime: Mapped[Optional[str]] = mapped_column(String(40))
    uf: Mapped[Optional[str]] = mapped_column(String(2))
    city_code: Mapped[Optional[str]] = mapped_column(String(20))
    address_line: Mapped[Optional[str]] = mapped_column(String(180))
    address_number: Mapped[Optional[str]] = mapped_column(String(20))
    neighborhood: Mapped[Optional[str]] = mapped_column(String(120))
    city: Mapped[Optional[str]] = mapped_column(String(120))
    zip_code: Mapped[Optional[str]] = mapped_column(String(20))
    environment: Mapped[str] = mapped_column(String(20), nullable=False, default="homologacao")
    nfce_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    pdv_nfce_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    nfe_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    certificate_name: Mapped[Optional[str]] = mapped_column(String(180))
    certificate_storage_key: Mapped[Optional[str]] = mapped_column(String(220))
    certificate_password_secret_key: Mapped[Optional[str]] = mapped_column(String(220))
    certificate_encrypted_blob: Mapped[Optional[bytes]] = mapped_column(LargeBinary)
    certificate_password_encrypted: Mapped[Optional[str]] = mapped_column(Text)
    certificate_file_sha256: Mapped[Optional[str]] = mapped_column(String(64))
    certificate_expires_at: Mapped[Optional[date]] = mapped_column(Date)
    certificate_uploaded_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    nfce_series: Mapped[int] = mapped_column(nullable=False, default=1)
    nfce_next_number: Mapped[int] = mapped_column(nullable=False, default=1)
    nfce_last_authorized_number: Mapped[Optional[int]] = mapped_column()
    nfe_series: Mapped[int] = mapped_column(nullable=False, default=1)
    nfe_next_number: Mapped[int] = mapped_column(nullable=False, default=1)
    nfe_last_authorized_number: Mapped[Optional[int]] = mapped_column()
    nfce_csc_id: Mapped[Optional[str]] = mapped_column(String(40))
    nfce_csc_secret_key: Mapped[Optional[str]] = mapped_column(String(220))
    logo_url: Mapped[Optional[str]] = mapped_column(Text)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class FiscalSettingsAuditLog(Base):
    __tablename__ = "fiscal_settings_audit_logs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    field_name: Mapped[Optional[str]] = mapped_column(String(80))
    old_value: Mapped[Optional[str]] = mapped_column(Text)
    new_value: Mapped[Optional[str]] = mapped_column(Text)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class FiscalDocument(Base):
    __tablename__ = "fiscal_documents"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sale_id: Mapped[Optional[int]] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), index=True)
    fiscal_client_id: Mapped[Optional[int]] = mapped_column(ForeignKey("clients.id", ondelete="SET NULL"), index=True)
    document_type: Mapped[str] = mapped_column(String(10), nullable=False, default="nfce")
    model: Mapped[str] = mapped_column(String(2), nullable=False, default="65")
    series: Mapped[Optional[int]] = mapped_column()
    number: Mapped[Optional[int]] = mapped_column(index=True)
    access_key: Mapped[Optional[str]] = mapped_column(String(60), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="draft")
    environment: Mapped[str] = mapped_column(String(20), nullable=False, default="homologacao")
    consumer_cpf: Mapped[Optional[str]] = mapped_column(String(14), index=True)
    recipient_document: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    recipient_name: Mapped[Optional[str]] = mapped_column(String(180))
    operation_nature: Mapped[Optional[str]] = mapped_column(String(120))
    finality: Mapped[str] = mapped_column(String(1), nullable=False, default="1")
    payment_condition: Mapped[Optional[str]] = mapped_column(String(20))
    fiscal_notes: Mapped[Optional[str]] = mapped_column(Text)
    freight_mode: Mapped[Optional[str]] = mapped_column(String(2))
    freight_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    insurance_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    other_expenses_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    carrier_name: Mapped[Optional[str]] = mapped_column(String(180))
    carrier_document: Mapped[Optional[str]] = mapped_column(String(20))
    carrier_state_registration: Mapped[Optional[str]] = mapped_column(String(20))
    carrier_address: Mapped[Optional[str]] = mapped_column(String(180))
    carrier_city: Mapped[Optional[str]] = mapped_column(String(120))
    carrier_uf: Mapped[Optional[str]] = mapped_column(String(2))
    volume_quantity: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 3))
    volume_species: Mapped[Optional[str]] = mapped_column(String(60))
    volume_brand: Mapped[Optional[str]] = mapped_column(String(60))
    volume_numbering: Mapped[Optional[str]] = mapped_column(String(60))
    net_weight: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 3))
    gross_weight: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 3))
    xml_generated: Mapped[Optional[str]] = mapped_column(Text)
    xml_signed: Mapped[Optional[str]] = mapped_column(Text)
    xml_authorized: Mapped[Optional[str]] = mapped_column(Text)
    sefaz_protocol: Mapped[Optional[str]] = mapped_column(String(80))
    sefaz_status_code: Mapped[Optional[str]] = mapped_column(String(20))
    sefaz_message: Mapped[Optional[str]] = mapped_column(Text)
    danfe_url: Mapped[Optional[str]] = mapped_column(String(500))
    sent_email_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    sent_whatsapp_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    issued_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    authorized_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    cancellation_reason: Mapped[Optional[str]] = mapped_column(String(255))
    cancellation_protocol: Mapped[Optional[str]] = mapped_column(String(80))
    cancellation_status_code: Mapped[Optional[str]] = mapped_column(String(20))
    cancellation_message: Mapped[Optional[str]] = mapped_column(Text)
    cancellation_xml: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    sale = relationship("Sale", back_populates="fiscal_documents")
    fiscal_client = relationship("Client")
    fiscal_items = relationship(
        "FiscalDocumentItem",
        back_populates="document",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class FiscalDocumentItem(Base):
    __tablename__ = "fiscal_document_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    fiscal_document_id: Mapped[int] = mapped_column(ForeignKey("fiscal_documents.id", ondelete="CASCADE"), index=True)
    sale_item_id: Mapped[Optional[int]] = mapped_column(ForeignKey("sale_items.id", ondelete="SET NULL"), index=True)
    original_product_id: Mapped[Optional[int]] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"), index=True)
    fiscal_product_id: Mapped[Optional[int]] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"), index=True)
    original_description: Mapped[Optional[str]] = mapped_column(String(220))
    fiscal_description: Mapped[str] = mapped_column(String(220), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=1)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    barcode: Mapped[Optional[str]] = mapped_column(String(80))
    included: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    adjustment_reason: Mapped[Optional[str]] = mapped_column(Text)
    ncm: Mapped[Optional[str]] = mapped_column(String(20))
    cest: Mapped[Optional[str]] = mapped_column(String(20))
    cfop: Mapped[Optional[str]] = mapped_column(String(10))
    origin: Mapped[Optional[str]] = mapped_column(String(2))
    cst: Mapped[Optional[str]] = mapped_column(String(10))
    csosn: Mapped[Optional[str]] = mapped_column(String(10))
    pis_cst: Mapped[Optional[str]] = mapped_column(String(10))
    cofins_cst: Mapped[Optional[str]] = mapped_column(String(10))
    cbenef: Mapped[Optional[str]] = mapped_column(String(20))
    created_by_user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    document = relationship("FiscalDocument", back_populates="fiscal_items")
    sale_item = relationship("SaleItem")
    original_product = relationship("Product", foreign_keys=[original_product_id])
    fiscal_product = relationship("Product", foreign_keys=[fiscal_product_id])

    @property
    def original_product_name(self) -> str | None:
        return self.original_product.name if self.original_product is not None else None

    @property
    def fiscal_product_name(self) -> str | None:
        return self.fiscal_product.name if self.fiscal_product is not None else None


class ProductTaxRule(Base):
    __tablename__ = "product_tax_rules"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    uf: Mapped[Optional[str]] = mapped_column(String(2))
    operation_type: Mapped[str] = mapped_column(String(30), nullable=False, default="sale")
    ncm: Mapped[Optional[str]] = mapped_column(String(20))
    cest: Mapped[Optional[str]] = mapped_column(String(20))
    cfop: Mapped[Optional[str]] = mapped_column(String(10))
    origin: Mapped[Optional[str]] = mapped_column(String(2))
    cst: Mapped[Optional[str]] = mapped_column(String(10))
    csosn: Mapped[Optional[str]] = mapped_column(String(10))
    pis_cst: Mapped[Optional[str]] = mapped_column(String(10))
    cofins_cst: Mapped[Optional[str]] = mapped_column(String(10))
    icms_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    pis_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    cofins_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_cbs_cst: Mapped[Optional[str]] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[Optional[str]] = mapped_column(String(20))
    cbs_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_state_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_city_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    selective_tax_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    effective_from: Mapped[Optional[date]] = mapped_column(Date)
    effective_to: Mapped[Optional[date]] = mapped_column(Date)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class FiscalOutputRule(Base):
    """Regra fiscal de saida por empresa.

    Esta tabela nao substitui o cadastro fiscal do produto nem o motor NF-e/NFC-e.
    Ela funciona como camada de decisao: por modelo, regime, UF, NCM/CEST ou produto.
    """

    __tablename__ = "fiscal_output_rules"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    priority: Mapped[int] = mapped_column(nullable=False, default=100)
    operation_type: Mapped[str] = mapped_column(String(30), nullable=False, default="sale")
    document_model: Mapped[Optional[str]] = mapped_column(String(10))
    tax_regime: Mapped[Optional[str]] = mapped_column(String(40))
    crt: Mapped[Optional[str]] = mapped_column(String(10))
    uf_origin: Mapped[Optional[str]] = mapped_column(String(2))
    uf_destination: Mapped[Optional[str]] = mapped_column(String(2))
    product_id: Mapped[Optional[int]] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"), index=True)
    ncm: Mapped[Optional[str]] = mapped_column(String(20))
    ncm_prefix: Mapped[Optional[str]] = mapped_column(String(20))
    cest: Mapped[Optional[str]] = mapped_column(String(20))
    cfop: Mapped[Optional[str]] = mapped_column(String(10))
    origin: Mapped[Optional[str]] = mapped_column(String(2))
    cst: Mapped[Optional[str]] = mapped_column(String(10))
    csosn: Mapped[Optional[str]] = mapped_column(String(10))
    pis_cst: Mapped[Optional[str]] = mapped_column(String(10))
    cofins_cst: Mapped[Optional[str]] = mapped_column(String(10))
    icms_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    pis_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    cofins_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_cbs_cst: Mapped[Optional[str]] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[Optional[str]] = mapped_column(String(20))
    cbs_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_state_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_city_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    selective_tax_cst: Mapped[Optional[str]] = mapped_column(String(10))
    selective_tax_classification: Mapped[Optional[str]] = mapped_column(String(20))
    selective_tax_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    effective_from: Mapped[Optional[date]] = mapped_column(Date)
    effective_to: Mapped[Optional[date]] = mapped_column(Date)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    product = relationship("Product")

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, computed_field

FiscalEnvironment = Literal["homologacao", "producao"]
FiscalDocumentType = Literal["nfce", "nfe"]
FiscalDocumentStatus = Literal[
    "draft",
    "pending_certificate",
    "xml_generated",
    "signed",
    "sent",
    "processing",
    "authorized",
    "rejected",
    "cancelled",
]


class CompanyFiscalSettingUpdate(BaseModel):
    legal_name: str | None = Field(default=None, max_length=180)
    trade_name: str | None = Field(default=None, max_length=180)
    cnpj: str | None = Field(default=None, max_length=20)
    state_registration: str | None = Field(default=None, max_length=40)
    municipal_registration: str | None = Field(default=None, max_length=40)
    crt: str | None = Field(default=None, max_length=10)
    tax_regime: str | None = Field(default=None, max_length=40)
    uf: str | None = Field(default=None, max_length=2)
    city_code: str | None = Field(default=None, max_length=20)
    address_line: str | None = Field(default=None, max_length=180)
    address_number: str | None = Field(default=None, max_length=20)
    neighborhood: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=120)
    zip_code: str | None = Field(default=None, max_length=20)
    environment: FiscalEnvironment = "homologacao"
    nfce_enabled: bool = False
    pdv_nfce_enabled: bool = False
    nfe_enabled: bool = False
    certificate_name: str | None = Field(default=None, max_length=180)
    certificate_storage_key: str | None = Field(default=None, max_length=220)
    certificate_password_secret_key: str | None = Field(default=None, max_length=220)
    certificate_expires_at: date | None = None
    nfce_series: int = Field(default=1, ge=1)
    nfce_next_number: int = Field(default=1, ge=1)
    nfe_series: int = Field(default=1, ge=1)
    nfe_next_number: int = Field(default=1, ge=1)
    nfce_csc_id: str | None = Field(default=None, max_length=40)
    nfce_csc_secret_key: str | None = Field(default=None, max_length=220)
    logo_url: str | None = None
    notes: str | None = None


class FiscalCertificateUploadRead(BaseModel):
    certificate_name: str
    certificate_file_sha256: str | None
    has_certificate: bool
    message: str


class NfceNumberingSyncRead(BaseModel):
    environment: FiscalEnvironment
    series: int
    current_next_number: int
    highest_authorized_number: int | None
    suggested_next_number: int
    updated_next_number: int
    keys_count: int
    incomplete: bool
    status_code: str | None
    message: str


class FiscalDocumentsRecoveryRead(BaseModel):
    imported: int
    updated: int
    skipped: int
    nfce_keys: int
    nfce_downloaded: int
    nfe_docs: int
    incomplete: bool
    ult_nsu: str | None = None
    max_nsu: str | None = None
    messages: list[str] = []


class FiscalSetupChecklistItem(BaseModel):
    code: str
    title: str
    status: Literal["ok", "pending", "attention"]
    owner: Literal["master", "cliente", "contador", "suporte"]
    message: str
    blocks_nfe: bool = False
    blocks_nfce: bool = False


class FiscalSetupChecklistRead(BaseModel):
    ready_for_nfe: bool
    ready_for_nfce: bool
    environment: FiscalEnvironment
    crt: str | None = None
    tax_regime: str | None = None
    items: list[FiscalSetupChecklistItem]


class CompanyFiscalSettingRead(BaseModel):
    id: int
    legal_name: str | None = None
    trade_name: str | None = None
    cnpj: str | None = None
    state_registration: str | None = None
    municipal_registration: str | None = None
    crt: str | None = None
    tax_regime: str | None = None
    uf: str | None = None
    city_code: str | None = None
    address_line: str | None = None
    address_number: str | None = None
    neighborhood: str | None = None
    city: str | None = None
    zip_code: str | None = None
    environment: FiscalEnvironment
    nfce_enabled: bool
    pdv_nfce_enabled: bool
    nfe_enabled: bool
    certificate_name: str | None
    certificate_storage_key: str | None = Field(default=None, exclude=True)
    certificate_encrypted_blob: bytes | None = Field(default=None, exclude=True)
    certificate_password_encrypted: str | None = Field(default=None, exclude=True)
    certificate_expires_at: date | None
    nfce_series: int
    nfce_next_number: int
    nfe_series: int
    nfe_next_number: int
    nfce_csc_id: str | None
    nfce_csc_secret_key: str | None = Field(default=None, exclude=True)
    logo_url: str | None = None
    notes: str | None
    certificate_uploaded_at: datetime | None
    certificate_file_sha256: str | None = None
    created_at: datetime
    updated_at: datetime

    @computed_field
    @property
    def has_certificate(self) -> bool:
        return bool(
            self.certificate_encrypted_blob
            and self.certificate_password_encrypted
            and self.certificate_storage_key
        )

    @computed_field
    @property
    def has_nfce_csc(self) -> bool:
        return bool(self.nfce_csc_id and self.nfce_csc_secret_key)

    model_config = ConfigDict(from_attributes=True)


class FiscalDocumentPrepare(BaseModel):
    sale_id: int
    fiscal_client_id: int | None = Field(default=None, gt=0)
    document_type: FiscalDocumentType = "nfce"
    consumer_cpf: str | None = Field(default=None, max_length=14)
    operation_nature: str | None = Field(default=None, max_length=120)
    payment_condition: Literal["vista", "prazo", "outros"] = "vista"
    fiscal_notes: str | None = Field(default=None, max_length=2000)


class FiscalDocumentItemDraftRead(BaseModel):
    id: int | None = None
    sale_item_id: int | None = None
    original_product_id: int | None = None
    original_product_name: str | None = None
    fiscal_product_id: int | None = None
    fiscal_product_name: str | None = None
    original_description: str | None = None
    fiscal_description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    discount_amount: Decimal = Decimal("0")
    total_price: Decimal
    barcode: str | None = None
    included: bool = True
    adjustment_reason: str | None = None

    model_config = ConfigDict(from_attributes=True)


class FiscalDocumentDraftRead(BaseModel):
    sale_id: int
    sale_number: str | None = None
    sale_total: Decimal
    fiscal_total: Decimal
    consumer_cpf: str | None = None
    items: list[FiscalDocumentItemDraftRead]


class FiscalDocumentItemOverride(BaseModel):
    sale_item_id: int | None = None
    fiscal_product_id: int | None = None
    fiscal_description: str | None = Field(default=None, max_length=220)
    quantity: Decimal = Field(gt=0)
    unit: str | None = Field(default=None, max_length=20)
    unit_price: Decimal = Field(ge=0)
    discount_amount: Decimal = Field(default=0, ge=0)
    included: bool = True
    adjustment_reason: str | None = Field(default=None, max_length=1000)


class FiscalDocumentPrepareWithItems(FiscalDocumentPrepare):
    items: list[FiscalDocumentItemOverride] = Field(min_length=1)


class FiscalDocumentPrepareManual(BaseModel):
    fiscal_client_id: int | None = Field(default=None, gt=0)
    document_type: FiscalDocumentType = "nfce"
    consumer_cpf: str | None = Field(default=None, max_length=14)
    operation_nature: str | None = Field(default=None, max_length=120)
    payment_condition: Literal["vista", "prazo", "outros"] = "vista"
    fiscal_notes: str | None = Field(default=None, max_length=2000)
    stock_deduction_on_authorize: bool = True
    items: list[FiscalDocumentItemOverride] = Field(min_length=1)


class FiscalProductLookupRead(BaseModel):
    id: int
    name: str
    internal_code: str | None = None
    barcode: str | None = None
    unit: str
    stock_quantity: Decimal
    fiscal_received_quantity: Decimal
    fiscal_issued_quantity: Decimal
    fiscal_available_quantity: Decimal
    fiscal_entry_count: int
    sale_price: Decimal

    model_config = ConfigDict(from_attributes=True)


class FiscalDocumentCancel(BaseModel):
    reason: str = Field(min_length=15, max_length=255)


class FiscalOutputRuleBase(BaseModel):
    name: str = Field(max_length=120)
    active: bool = True
    priority: int = Field(default=100, ge=1, le=9999)
    operation_type: str = Field(default="sale", max_length=30)
    document_model: str | None = Field(default=None, max_length=10)
    tax_regime: str | None = Field(default=None, max_length=40)
    crt: str | None = Field(default=None, max_length=10)
    uf_origin: str | None = Field(default=None, max_length=2)
    uf_destination: str | None = Field(default=None, max_length=2)
    product_id: int | None = Field(default=None, gt=0)
    ncm: str | None = Field(default=None, max_length=20)
    ncm_prefix: str | None = Field(default=None, max_length=20)
    cest: str | None = Field(default=None, max_length=20)
    cfop: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    pis_cst: str | None = Field(default=None, max_length=10)
    cofins_cst: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    effective_from: date | None = None
    effective_to: date | None = None
    notes: str | None = None


class FiscalOutputRuleCreate(FiscalOutputRuleBase):
    pass


class FiscalOutputRuleUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    active: bool | None = None
    priority: int | None = Field(default=None, ge=1, le=9999)
    operation_type: str | None = Field(default=None, max_length=30)
    document_model: str | None = Field(default=None, max_length=10)
    tax_regime: str | None = Field(default=None, max_length=40)
    crt: str | None = Field(default=None, max_length=10)
    uf_origin: str | None = Field(default=None, max_length=2)
    uf_destination: str | None = Field(default=None, max_length=2)
    product_id: int | None = Field(default=None, gt=0)
    ncm: str | None = Field(default=None, max_length=20)
    ncm_prefix: str | None = Field(default=None, max_length=20)
    cest: str | None = Field(default=None, max_length=20)
    cfop: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    pis_cst: str | None = Field(default=None, max_length=10)
    cofins_cst: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    effective_from: date | None = None
    effective_to: date | None = None
    notes: str | None = None


class FiscalOutputRuleRead(FiscalOutputRuleBase):
    id: int
    product_name: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FiscalDocumentRead(BaseModel):
    id: int
    sale_id: int | None
    fiscal_client_id: int | None = None
    document_type: FiscalDocumentType
    model: str
    series: int | None
    number: int | None
    access_key: str | None
    status: FiscalDocumentStatus
    environment: FiscalEnvironment
    consumer_cpf: str | None
    recipient_document: str | None
    recipient_name: str | None
    operation_nature: str | None
    payment_condition: str | None
    fiscal_notes: str | None
    sefaz_protocol: str | None
    sefaz_status_code: str | None
    sefaz_message: str | None
    danfe_url: str | None
    issued_at: datetime | None
    authorized_at: datetime | None
    cancelled_at: datetime | None
    cancellation_reason: str | None
    cancellation_protocol: str | None
    cancellation_status_code: str | None
    cancellation_message: str | None
    fiscal_items: list[FiscalDocumentItemDraftRead] = []
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

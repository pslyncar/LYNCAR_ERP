from datetime import date, datetime
from decimal import Decimal

from typing import Literal

from pydantic import BaseModel, Field


class StockEntryItemCreate(BaseModel):
    product_id: int | None = None
    description: str = Field(min_length=1, max_length=220)
    barcode: str | None = Field(default=None, max_length=80)
    tax_gtin: str | None = Field(default=None, max_length=80)
    supplier_product_code: str | None = Field(default=None, max_length=80)
    invoice_quantity: Decimal | None = Field(default=None, ge=0)
    invoice_unit: str | None = Field(default=None, max_length=20)
    tax_quantity: Decimal | None = Field(default=None, ge=0)
    tax_unit: str | None = Field(default=None, max_length=20)
    package_conversion_factor: Decimal | None = Field(default=None, gt=0)
    quantity: Decimal = Field(gt=0)
    received_quantity: Decimal | None = Field(default=None, ge=0)
    approved_quantity: Decimal | None = Field(default=None, ge=0)
    unit: str = Field(default="un", max_length=20)
    unit_cost: Decimal = Field(ge=0)
    total_cost: Decimal | None = Field(default=None, ge=0)
    ncm: str | None = Field(default=None, max_length=20)
    cfop: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ipi_rate: Decimal | None = Field(default=None, ge=0)
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    batch_number: str | None = Field(default=None, max_length=80)
    expiration_date: date | None = None
    manufacturing_date: date | None = None
    temperature_celsius: Decimal | None = None
    discrepancy_reason: str | None = Field(default=None, max_length=120)
    storage_location: str | None = Field(default=None, max_length=120)
    check_status: str = Field(default="accepted", max_length=30)
    check_notes: str | None = None


class StockEntryCreate(BaseModel):
    supplier_id: int | None = None
    supplier_name: str | None = Field(default=None, max_length=180)
    supplier_document: str | None = Field(default=None, max_length=30)
    source: str = Field(default="manual", max_length=30)
    invoice_key: str | None = Field(default=None, max_length=60)
    invoice_number: str | None = Field(default=None, max_length=30)
    invoice_series: str | None = Field(default=None, max_length=20)
    notes: str | None = None
    items: list[StockEntryItemCreate] = Field(min_length=1)


class StockEntryMobileReceiveItem(BaseModel):
    product_id: int | None = None
    description: str = Field(min_length=1, max_length=220)
    barcode: str | None = Field(default=None, max_length=80)
    quantity: Decimal = Field(gt=0)
    unit: str = Field(default="un", max_length=20)
    unit_cost: Decimal = Field(ge=0)
    sale_price: Decimal | None = Field(default=None, ge=0)
    ncm: str | None = Field(default=None, max_length=20)
    cfop: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ipi_rate: Decimal | None = Field(default=None, ge=0)
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    batch_number: str | None = Field(default=None, max_length=80)
    expiration_date: date | None = None
    manufacturing_date: date | None = None
    temperature_celsius: Decimal | None = None
    discrepancy_reason: str | None = Field(default=None, max_length=120)
    storage_location: str | None = Field(default=None, max_length=120)
    check_status: Literal["accepted", "return"] = "accepted"
    check_notes: str | None = None


class StockEntryItemMatchRequest(BaseModel):
    product_id: int = Field(gt=0)
    remember_supplier_link: bool = True
    supplier_product_code: str | None = Field(default=None, max_length=80)
    commercial_gtin: str | None = Field(default=None, max_length=80)
    tax_gtin: str | None = Field(default=None, max_length=80)
    supplier_description: str | None = Field(default=None, max_length=220)
    supplier_unit: str | None = Field(default=None, max_length=20)
    stock_unit: str | None = Field(default=None, max_length=20)
    conversion_factor: Decimal | None = Field(default=None, gt=0)


class StockEntryProductSuggestion(BaseModel):
    product_id: int
    name: str
    internal_code: str | None = None
    barcode: str | None = None
    purchase_package_barcode: str | None = None
    unit: str
    match_method: str
    warning: str | None = None


class StockEntryItemLotCreate(BaseModel):
    lot_number: str | None = Field(default=None, max_length=80)
    manufacturing_date: date | None = None
    expiration_date: date | None = None
    quantity: Decimal = Field(gt=0)
    temperature_celsius: Decimal | None = None
    notes: str | None = None


class StockEntryItemLotRead(BaseModel):
    id: int
    stock_entry_item_id: int
    lot_number: str | None
    manufacturing_date: date | None
    expiration_date: date | None
    quantity: Decimal
    temperature_celsius: Decimal | None
    notes: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class StockEntryItemRead(BaseModel):
    id: int
    product_id: int | None
    description: str
    barcode: str | None
    tax_gtin: str | None = None
    supplier_product_code: str | None = None
    invoice_quantity: Decimal | None = None
    invoice_unit: str | None = None
    tax_quantity: Decimal | None = None
    tax_unit: str | None = None
    package_conversion_factor: Decimal | None = None
    quantity: Decimal
    received_quantity: Decimal | None
    unit: str
    unit_cost: Decimal
    total_cost: Decimal
    ncm: str | None
    cfop: str | None
    origin: str | None
    cst: str | None
    csosn: str | None
    icms_rate: Decimal | None
    pis_rate: Decimal | None
    cofins_rate: Decimal | None
    ipi_rate: Decimal | None
    ibs_cbs_cst: str | None
    ibs_cbs_classification: str | None
    cbs_rate: Decimal | None
    ibs_state_rate: Decimal | None
    ibs_city_rate: Decimal | None
    selective_tax_cst: str | None
    selective_tax_classification: str | None
    selective_tax_rate: Decimal | None
    batch_number: str | None
    expiration_date: date | None
    manufacturing_date: date | None = None
    temperature_celsius: Decimal | None = None
    discrepancy_reason: str | None = None
    storage_location: str | None = None
    check_status: str
    check_notes: str | None
    lots: list["StockEntryItemLotRead"] = []
    created_at: datetime

    model_config = {"from_attributes": True}


class StockEntryRead(BaseModel):
    id: int
    supplier_id: int | None
    user_id: int | None
    source: str
    status: str
    invoice_key: str | None
    invoice_number: str | None
    invoice_series: str | None
    supplier_name: str | None
    supplier_document: str | None
    total_amount: Decimal
    notes: str | None
    confirmed_at: datetime | None
    reversed_at: datetime | None = None
    reversal_reason: str | None = None
    created_at: datetime
    items: list[StockEntryItemRead] = []

    model_config = {"from_attributes": True}


class StockDevolutionDraftItemRead(BaseModel):
    stock_entry_item_id: int
    product_id: int
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    total_price: Decimal
    reason: str


class StockDevolutionDraftRead(BaseModel):
    fiscal_document_id: int
    stock_entry_id: int
    mode: str
    status: str
    supplier_name: str | None
    supplier_document: str | None
    original_invoice_number: str | None
    original_invoice_key: str | None
    total_amount: Decimal
    items: list[StockDevolutionDraftItemRead]


class StockReceiptPage(BaseModel):
    items: list[StockEntryRead]
    total: int
    page: int
    page_size: int


class StockReceiptSummary(BaseModel):
    all: int
    receiving: int
    pending_products: int
    divergences: int
    confirmed: int


class ReceivingSessionCreate(BaseModel):
    device_id: str | None = Field(default=None, max_length=120)


class StockEntryReversalRequest(BaseModel):
    reason: str = Field(min_length=5, max_length=500)


class ReceivingScanCreate(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=120)
    stock_entry_item_id: int | None = Field(default=None, gt=0)
    barcode: str | None = Field(default=None, max_length=80)
    quantity: Decimal = Field(gt=0)
    unit: str = Field(default="un", max_length=20)
    batch_number: str | None = Field(default=None, max_length=80)
    expiration_date: date | None = None
    condition: str = Field(default="ok", max_length=30)
    notes: str | None = None


class ReceivingSessionRead(BaseModel):
    id: int
    stock_entry_id: int
    user_id: int | None
    device_id: str | None
    status: str
    started_at: datetime
    finished_at: datetime | None
    scan_count: int = 0
    total_quantity: Decimal = Decimal("0")

    model_config = {"from_attributes": True}


class NfeXmlPreviewItem(BaseModel):
    product_id: int | None = None
    product_name: str | None = None
    description: str
    barcode: str | None = None
    tax_gtin: str | None = None
    supplier_product_code: str | None = None
    matching_status: str = "pending"
    matching_method: str | None = None
    match_suggestions: list[int] = []
    quantity: Decimal
    unit: str
    tax_quantity: Decimal | None = None
    tax_unit: str | None = None
    unit_cost: Decimal
    total_cost: Decimal
    ncm: str | None = None
    cfop: str | None = None
    origin: str | None = None
    cst: str | None = None
    csosn: str | None = None
    icms_rate: Decimal | None = None
    pis_rate: Decimal | None = None
    cofins_rate: Decimal | None = None
    ipi_rate: Decimal | None = None
    ibs_cbs_cst: str | None = None
    ibs_cbs_classification: str | None = None
    cbs_rate: Decimal | None = None
    ibs_state_rate: Decimal | None = None
    ibs_city_rate: Decimal | None = None
    selective_tax_cst: str | None = None
    selective_tax_classification: str | None = None
    selective_tax_rate: Decimal | None = None
    batch_number: str | None = None
    expiration_date: date | None = None


class NfeXmlPreview(BaseModel):
    supplier_id: int | None = None
    supplier_name: str | None = None
    supplier_document: str | None = None
    invoice_key: str | None = None
    invoice_number: str | None = None
    invoice_series: str | None = None
    items: list[NfeXmlPreviewItem]


class NfeXmlImportRequest(BaseModel):
    xml_content: str = Field(min_length=20)


class NfeKeyDownloadRequest(BaseModel):
    access_key: str = Field(min_length=44, max_length=60)

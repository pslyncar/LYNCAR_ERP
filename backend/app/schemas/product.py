from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

ProductType = Literal[
    "produto",
    "produto_acabado",
    "mercadoria",
    "materia_prima",
    "embalagem",
    "peca",
    "servico",
    "insumo",
]


class ProductBase(BaseModel):
    name: str = Field(min_length=2, max_length=180)
    product_type: ProductType = "servico"
    internal_code: str | None = Field(default=None, max_length=60)
    barcode: str | None = Field(default=None, max_length=80)
    image_url: str | None = None
    description: str | None = None
    brand: str | None = Field(default=None, max_length=100)
    model: str | None = Field(default=None, max_length=100)
    category: str | None = Field(default=None, max_length=100)
    stock_location: str | None = Field(default=None, max_length=120)
    tracks_batch: bool = False
    initial_batch_number: str | None = Field(default=None, max_length=80)
    initial_expiration_date: date | None = None
    sale_price: Decimal = Field(default=0, ge=0)
    offer_price: Decimal | None = Field(default=None, ge=0)
    offer_start_at: datetime | None = None
    offer_end_at: datetime | None = None
    purchase_total_cost: Decimal | None = Field(default=None, ge=0)
    purchase_quantity: Decimal | None = Field(default=None, gt=0)
    average_cost: Decimal | None = Field(default=None, ge=0)
    purchase_conversion_enabled: bool = False
    purchase_invoice_unit: str | None = Field(default=None, max_length=20)
    purchase_package_factor: Decimal | None = Field(default=None, gt=0)
    purchase_package_barcode: str | None = Field(default=None, max_length=80)
    margin_percent: Decimal | None = Field(default=None, ge=0)
    stock_quantity: Decimal = Field(default=0)
    fiscal_received_quantity: Decimal = Field(default=0, ge=0)
    fiscal_issued_quantity: Decimal = Field(default=0, ge=0)
    fiscal_available_quantity: Decimal = Field(default=0, ge=0)
    fiscal_entry_count: int = Field(default=0, ge=0)
    minimum_stock: Decimal = Field(default=0, ge=0)
    unit: str = Field(default="un", max_length=20)
    ncm: str | None = Field(default=None, max_length=20)
    cest: str | None = Field(default=None, max_length=20)
    cfop_sale: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ipi_rate: Decimal | None = Field(default=None, ge=0)
    iss_rate: Decimal | None = Field(default=None, ge=0)
    municipal_service_code: str | None = Field(default=None, max_length=40)
    tax_rate: Decimal | None = Field(default=None, ge=0)
    fiscal_notes: str | None = None
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    new_tax_system: bool = False
    old_tax_system_notes: str | None = None
    new_tax_system_notes: str | None = None
    active: bool = True
    notes: str | None = None


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=180)
    product_type: ProductType | None = None
    internal_code: str | None = Field(default=None, max_length=60)
    barcode: str | None = Field(default=None, max_length=80)
    image_url: str | None = None
    description: str | None = None
    brand: str | None = Field(default=None, max_length=100)
    model: str | None = Field(default=None, max_length=100)
    category: str | None = Field(default=None, max_length=100)
    stock_location: str | None = Field(default=None, max_length=120)
    tracks_batch: bool | None = None
    initial_batch_number: str | None = Field(default=None, max_length=80)
    initial_expiration_date: date | None = None
    sale_price: Decimal | None = Field(default=None, ge=0)
    offer_price: Decimal | None = Field(default=None, ge=0)
    offer_start_at: datetime | None = None
    offer_end_at: datetime | None = None
    purchase_total_cost: Decimal | None = Field(default=None, ge=0)
    purchase_quantity: Decimal | None = Field(default=None, gt=0)
    average_cost: Decimal | None = Field(default=None, ge=0)
    purchase_conversion_enabled: bool | None = None
    purchase_invoice_unit: str | None = Field(default=None, max_length=20)
    purchase_package_factor: Decimal | None = Field(default=None, gt=0)
    purchase_package_barcode: str | None = Field(default=None, max_length=80)
    margin_percent: Decimal | None = Field(default=None, ge=0)
    stock_quantity: Decimal | None = Field(default=None)
    fiscal_received_quantity: Decimal | None = Field(default=None, ge=0)
    fiscal_issued_quantity: Decimal | None = Field(default=None, ge=0)
    fiscal_available_quantity: Decimal | None = Field(default=None, ge=0)
    fiscal_entry_count: int | None = Field(default=None, ge=0)
    minimum_stock: Decimal | None = Field(default=None, ge=0)
    unit: str | None = Field(default=None, max_length=20)
    ncm: str | None = Field(default=None, max_length=20)
    cest: str | None = Field(default=None, max_length=20)
    cfop_sale: str | None = Field(default=None, max_length=10)
    origin: str | None = Field(default=None, max_length=2)
    cst: str | None = Field(default=None, max_length=10)
    csosn: str | None = Field(default=None, max_length=10)
    icms_rate: Decimal | None = Field(default=None, ge=0)
    pis_rate: Decimal | None = Field(default=None, ge=0)
    cofins_rate: Decimal | None = Field(default=None, ge=0)
    ipi_rate: Decimal | None = Field(default=None, ge=0)
    iss_rate: Decimal | None = Field(default=None, ge=0)
    municipal_service_code: str | None = Field(default=None, max_length=40)
    tax_rate: Decimal | None = Field(default=None, ge=0)
    fiscal_notes: str | None = None
    ibs_cbs_cst: str | None = Field(default=None, max_length=10)
    ibs_cbs_classification: str | None = Field(default=None, max_length=20)
    cbs_rate: Decimal | None = Field(default=None, ge=0)
    ibs_state_rate: Decimal | None = Field(default=None, ge=0)
    ibs_city_rate: Decimal | None = Field(default=None, ge=0)
    selective_tax_cst: str | None = Field(default=None, max_length=10)
    selective_tax_classification: str | None = Field(default=None, max_length=20)
    selective_tax_rate: Decimal | None = Field(default=None, ge=0)
    new_tax_system: bool | None = None
    old_tax_system_notes: str | None = None
    new_tax_system_notes: str | None = None
    active: bool | None = None
    notes: str | None = None


class ProductRead(ProductBase):
    id: int
    average_cost: Decimal | None
    stock_value: Decimal
    nearest_batch_number: str | None = None
    nearest_expiration_date: date | None = None
    last_receipt_supplier_name: str | None = None
    last_receipt_invoice_number: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

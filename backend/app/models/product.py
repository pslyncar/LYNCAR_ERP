from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(180), nullable=False)
    product_type: Mapped[str] = mapped_column(String(20), nullable=False, default="servico")
    internal_code: Mapped[Optional[str]] = mapped_column(String(60), unique=True)
    barcode: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    image_url: Mapped[Optional[str]] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)
    brand: Mapped[Optional[str]] = mapped_column(String(100))
    model: Mapped[Optional[str]] = mapped_column(String(100))
    category: Mapped[Optional[str]] = mapped_column(String(100))
    stock_location: Mapped[Optional[str]] = mapped_column(String(120))
    tracks_batch: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    initial_batch_number: Mapped[Optional[str]] = mapped_column(String(80))
    initial_expiration_date: Mapped[Optional[date]] = mapped_column(Date)
    sale_price: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=0)
    offer_price: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4))
    offer_start_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    offer_end_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    purchase_total_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    purchase_quantity: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 3))
    purchase_conversion_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    purchase_invoice_unit: Mapped[Optional[str]] = mapped_column(String(20))
    purchase_package_factor: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4))
    purchase_package_barcode: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    average_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4))
    stock_value: Mapped[Decimal] = mapped_column(Numeric(14, 4), nullable=False, default=0)
    margin_percent: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 2))
    stock_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    fiscal_received_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    fiscal_issued_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    fiscal_available_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    fiscal_entry_count: Mapped[int] = mapped_column(nullable=False, default=0)
    minimum_stock: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    ncm: Mapped[Optional[str]] = mapped_column(String(20))
    cest: Mapped[Optional[str]] = mapped_column(String(20))
    cfop_sale: Mapped[Optional[str]] = mapped_column(String(10))
    origin: Mapped[Optional[str]] = mapped_column(String(2))
    cst: Mapped[Optional[str]] = mapped_column(String(10))
    csosn: Mapped[Optional[str]] = mapped_column(String(10))
    icms_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    pis_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    cofins_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ipi_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    iss_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    municipal_service_code: Mapped[Optional[str]] = mapped_column(String(40))
    tax_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    fiscal_notes: Mapped[Optional[str]] = mapped_column(Text)
    ibs_cbs_cst: Mapped[Optional[str]] = mapped_column(String(10))
    ibs_cbs_classification: Mapped[Optional[str]] = mapped_column(String(20))
    cbs_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_state_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    ibs_city_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    selective_tax_cst: Mapped[Optional[str]] = mapped_column(String(10))
    selective_tax_classification: Mapped[Optional[str]] = mapped_column(String(20))
    selective_tax_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4))
    new_tax_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    old_tax_system_notes: Mapped[Optional[str]] = mapped_column(Text)
    new_tax_system_notes: Mapped[Optional[str]] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    service_order_items = relationship("ServiceOrderItem", back_populates="product")
    sale_items = relationship("SaleItem", back_populates="product")
    tax_rules = relationship("ProductTaxRule", cascade="all, delete-orphan")
    stock_movements = relationship("StockMovement", back_populates="product")
    batches = relationship("ProductBatch", back_populates="product", cascade="all, delete-orphan")
    composition_items = relationship(
        "ProductCompositionItem",
        back_populates="product",
        foreign_keys="ProductCompositionItem.product_id",
        cascade="all, delete-orphan",
    )
    used_in_compositions = relationship(
        "ProductCompositionItem",
        back_populates="component_product",
        foreign_keys="ProductCompositionItem.component_product_id",
    )

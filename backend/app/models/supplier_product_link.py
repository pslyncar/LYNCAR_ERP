from datetime import datetime
from decimal import Decimal

from sqlalchemy import Boolean, DateTime, ForeignKey, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class SupplierProductLink(Base):
    """Explicit reconciliation between a supplier code and an internal product.

    The supplier's ``cProd`` is not an internal SKU.  This table keeps the
    decision made by an operator and lets future XMLs reuse it safely.
    """

    __tablename__ = "supplier_product_links"
    __table_args__ = (
        UniqueConstraint("supplier_id", "supplier_product_code", name="uq_supplier_product_link_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    supplier_id: Mapped[int] = mapped_column(ForeignKey("suppliers.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
    supplier_product_code: Mapped[str] = mapped_column(String(80), nullable=False)
    supplier_description: Mapped[str | None] = mapped_column(String(220))
    commercial_gtin: Mapped[str | None] = mapped_column(String(20), index=True)
    tax_gtin: Mapped[str | None] = mapped_column(String(20), index=True)
    supplier_unit: Mapped[str | None] = mapped_column(String(20))
    stock_unit: Mapped[str | None] = mapped_column(String(20))
    conversion_factor: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    supplier = relationship("Supplier", back_populates="product_links")
    product = relationship("Product", back_populates="supplier_links")

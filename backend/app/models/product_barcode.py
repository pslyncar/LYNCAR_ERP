from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ProductBarcode(Base):
    """Additional barcodes kept independently from the product master.

    A barcode is intentionally not globally unique: duplicate GTINs must be
    detectable and shown as an ambiguity instead of being silently matched.
    """

    __tablename__ = "product_barcodes"
    __table_args__ = (
        UniqueConstraint("product_id", "barcode", name="uq_product_barcode_product"),
        Index("ix_product_barcodes_barcode", "barcode"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)
    barcode: Mapped[str] = mapped_column(String(80), nullable=False)
    barcode_type: Mapped[str] = mapped_column(String(20), nullable=False, default="gtin")
    active: Mapped[bool] = mapped_column(nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    product = relationship("Product", back_populates="barcodes")

from datetime import date
from decimal import Decimal

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.product import Product
from app.models.product_batch import ProductBatch


def _normalized_batch(value: str | None) -> str | None:
    trimmed = value.strip() if value else None
    return trimmed or None


def _same_batch_filter(product_id: int, batch_number: str | None, expiration_date: date | None):
    batch_number = _normalized_batch(batch_number)
    batch_filter = ProductBatch.batch_number.is_(None) if batch_number is None else ProductBatch.batch_number == batch_number
    expiration_filter = (
        ProductBatch.expiration_date.is_(None)
        if expiration_date is None
        else ProductBatch.expiration_date == expiration_date
    )
    return ProductBatch.product_id == product_id, batch_filter, expiration_filter


def upsert_product_batch(
    db: Session,
    product: Product,
    quantity: Decimal,
    *,
    batch_number: str | None = None,
    expiration_date: date | None = None,
    source_type: str | None = None,
    source_id: int | None = None,
    source_number: str | None = None,
    supplier_name: str | None = None,
    invoice_number: str | None = None,
    invoice_series: str | None = None,
    notes: str | None = None,
) -> ProductBatch | None:
    if quantity <= 0:
        return None
    normalized_batch = _normalized_batch(batch_number)
    if not product.tracks_batch and normalized_batch is None and expiration_date is None:
        return None

    product.tracks_batch = True
    batch = db.scalar(
        select(ProductBatch).where(
            *_same_batch_filter(product.id, normalized_batch, expiration_date),
            ProductBatch.active.is_(True),
        )
    )
    if batch is None:
        batch = ProductBatch(
            product_id=product.id,
            batch_number=normalized_batch,
            expiration_date=expiration_date,
            quantity=quantity,
            unit=product.unit,
            source_type=source_type,
            source_id=source_id,
            source_number=source_number,
            supplier_name=supplier_name,
            invoice_number=invoice_number,
            invoice_series=invoice_series,
            notes=notes,
        )
        db.add(batch)
    else:
        batch.quantity += quantity
        batch.unit = product.unit
        batch.source_type = source_type or batch.source_type
        batch.source_id = source_id or batch.source_id
        batch.source_number = source_number or batch.source_number
        batch.supplier_name = supplier_name or batch.supplier_name
        batch.invoice_number = invoice_number or batch.invoice_number
        batch.invoice_series = invoice_series or batch.invoice_series
        batch.notes = notes or batch.notes
    return batch


def ensure_initial_product_batch(db: Session, product: Product) -> ProductBatch | None:
    if product.stock_quantity <= 0:
        return None
    if not product.tracks_batch and not product.initial_batch_number and not product.initial_expiration_date:
        return None
    existing = db.scalar(
        select(ProductBatch.id).where(ProductBatch.product_id == product.id).limit(1)
    )
    if existing is not None:
        return None
    return upsert_product_batch(
        db,
        product,
        product.stock_quantity,
        batch_number=product.initial_batch_number,
        expiration_date=product.initial_expiration_date,
        source_type="product_initial",
        source_id=product.id,
        source_number=product.internal_code,
        notes="Saldo inicial informado no cadastro do produto.",
    )


def apply_batch_out(
    db: Session,
    product: Product,
    quantity: Decimal,
    *,
    source_type: str | None = None,
    source_id: int | None = None,
    source_number: str | None = None,
) -> None:
    if quantity <= 0 or not product.tracks_batch:
        return
    remaining = quantity
    batches = list(
        db.scalars(
            select(ProductBatch)
            .where(
                ProductBatch.product_id == product.id,
                ProductBatch.active.is_(True),
                ProductBatch.quantity > 0,
            )
            .order_by(
                ProductBatch.expiration_date.asc().nulls_last(),
                ProductBatch.created_at.asc(),
                ProductBatch.id.asc(),
            )
        ).all()
    )
    for batch in batches:
        if remaining <= 0:
            break
        used = min(batch.quantity, remaining)
        batch.quantity -= used
        batch.source_type = source_type or batch.source_type
        batch.source_id = source_id or batch.source_id
        batch.source_number = source_number or batch.source_number
        remaining -= used


def return_to_batch(
    db: Session,
    product: Product,
    quantity: Decimal,
    *,
    source_type: str | None = None,
    source_id: int | None = None,
    source_number: str | None = None,
) -> ProductBatch | None:
    return upsert_product_batch(
        db,
        product,
        quantity,
        batch_number="RETORNO",
        source_type=source_type,
        source_id=source_id,
        source_number=source_number,
        notes="Saldo devolvido por cancelamento/estorno.",
    )


def list_available_batches(db: Session, product_id: int) -> list[ProductBatch]:
    return list(
        db.scalars(
            select(ProductBatch)
            .where(
                ProductBatch.product_id == product_id,
                ProductBatch.active.is_(True),
                or_(ProductBatch.quantity > 0, ProductBatch.source_type == "product_initial"),
            )
            .order_by(
                ProductBatch.expiration_date.asc().nulls_last(),
                ProductBatch.created_at.desc(),
                ProductBatch.id.desc(),
            )
        ).all()
    )

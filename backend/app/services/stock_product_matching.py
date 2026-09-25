from dataclasses import dataclass
from difflib import SequenceMatcher
import re

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.product import Product
from app.models.product_barcode import ProductBarcode
from app.models.supplier_product_link import SupplierProductLink


def normalize_product_code(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = "".join(char for char in value.strip().upper() if char.isalnum())
    return normalized or None


def normalize_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", (value or "").strip().casefold())


@dataclass(frozen=True)
class ProductMatch:
    status: str
    product: Product | None
    method: str | None
    candidates: tuple[Product, ...] = ()


def _unique(products: list[Product]) -> list[Product]:
    result: list[Product] = []
    seen: set[int] = set()
    for product in products:
        if product.id in seen:
            continue
        seen.add(product.id)
        result.append(product)
    return result


def resolve_product_match(
    db: Session,
    *,
    supplier_id: int | None,
    supplier_product_code: str | None,
    commercial_gtin: str | None,
    tax_gtin: str | None,
    internal_code: str | None,
    description: str | None,
) -> ProductMatch:
    """Resolve only deterministic matches; descriptions produce suggestions only."""

    code = normalize_product_code(supplier_product_code)
    if supplier_id is not None and code:
        link = db.scalar(
            select(SupplierProductLink)
            .where(
                SupplierProductLink.supplier_id == supplier_id,
                SupplierProductLink.supplier_product_code == code,
            )
        )
        if link is not None:
            product = db.get(Product, link.product_id)
            if product is not None and product.active:
                return ProductMatch("matched", product, "supplier_code")

    gtins = {value for value in (normalize_product_code(commercial_gtin), normalize_product_code(tax_gtin)) if value}
    if gtins:
        barcode_rows = list(
            db.scalars(
                select(ProductBarcode)
                .where(ProductBarcode.active.is_(True), ProductBarcode.barcode.in_(gtins))
            ).all()
        )
        products = _unique([row.product for row in barcode_rows if row.product is not None and row.product.active])
        for field in (Product.barcode, Product.purchase_package_barcode):
            products.extend(
                db.scalars(select(Product).where(Product.active.is_(True), field.in_(gtins))).all()
            )
        products = _unique(products)
        if len(products) == 1:
            return ProductMatch("matched", products[0], "gtin")
        if len(products) > 1:
            return ProductMatch("ambiguous", None, "gtin", tuple(products))

    normalized_internal = normalize_product_code(internal_code)
    if normalized_internal:
        products = [
            product
            for product in db.scalars(select(Product).where(Product.active.is_(True))).all()
            if normalize_product_code(product.internal_code) == normalized_internal
        ]
        if len(products) == 1:
            return ProductMatch("matched", products[0], "internal_code")
        if len(products) > 1:
            return ProductMatch("ambiguous", None, "internal_code", tuple(products))

    normalized_description = normalize_text(description)
    if normalized_description:
        suggestions = []
        for product in db.scalars(select(Product).where(Product.active.is_(True))).all():
            score = SequenceMatcher(None, normalized_description, normalize_text(product.name)).ratio()
            if score >= 0.72:
                suggestions.append((score, product))
        suggestions.sort(key=lambda pair: pair[0], reverse=True)
        return ProductMatch("pending", None, "description_suggestion", tuple(product for _, product in suggestions[:5]))

    return ProductMatch("pending", None, None)

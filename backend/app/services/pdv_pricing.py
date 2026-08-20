from datetime import datetime, timezone
from decimal import Decimal

from app.models.product import Product


def effective_product_sale_price(
    product: Product,
    *,
    now: datetime | None = None,
) -> Decimal:
    current = now or datetime.now(timezone.utc)
    start = product.offer_start_at
    end = product.offer_end_at
    if start is not None and start.tzinfo is None:
        start = start.replace(tzinfo=timezone.utc)
    if end is not None and end.tzinfo is None:
        end = end.replace(tzinfo=timezone.utc)
    if (
        product.offer_price is not None
        and start is not None
        and end is not None
        and start <= current <= end
    ):
        return Decimal(product.offer_price)
    return Decimal(product.sale_price)

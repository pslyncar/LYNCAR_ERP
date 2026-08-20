from datetime import datetime, timedelta, timezone
from decimal import Decimal
from types import SimpleNamespace

from app.services.pdv_pricing import effective_product_sale_price


def _product(**overrides: object) -> SimpleNamespace:
    values = {
        "sale_price": Decimal("6.75"),
        "offer_price": None,
        "offer_start_at": None,
        "offer_end_at": None,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_effective_price_uses_active_offer() -> None:
    now = datetime(2026, 8, 20, 15, tzinfo=timezone.utc)
    product = _product(
        offer_price=Decimal("5.00"),
        offer_start_at=now - timedelta(hours=1),
        offer_end_at=now + timedelta(hours=1),
    )

    assert effective_product_sale_price(product, now=now) == Decimal("5.00")


def test_effective_price_ignores_scheduled_and_expired_offer() -> None:
    now = datetime(2026, 8, 20, 15, tzinfo=timezone.utc)
    scheduled = _product(
        offer_price=Decimal("5.00"),
        offer_start_at=now + timedelta(minutes=1),
        offer_end_at=now + timedelta(hours=1),
    )
    expired = _product(
        offer_price=Decimal("5.00"),
        offer_start_at=now - timedelta(hours=2),
        offer_end_at=now - timedelta(minutes=1),
    )

    assert effective_product_sale_price(scheduled, now=now) == Decimal("6.75")
    assert effective_product_sale_price(expired, now=now) == Decimal("6.75")


def test_effective_price_accepts_database_naive_datetimes_as_utc() -> None:
    now = datetime(2026, 8, 20, 15, tzinfo=timezone.utc)
    product = _product(
        offer_price=Decimal("5.00"),
        offer_start_at=datetime(2026, 8, 20, 14),
        offer_end_at=datetime(2026, 8, 20, 16),
    )

    assert effective_product_sale_price(product, now=now) == Decimal("5.00")

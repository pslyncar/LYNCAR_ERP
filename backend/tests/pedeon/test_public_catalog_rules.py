import unittest
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from types import SimpleNamespace

from app.modules.pedeon.application.public_catalog_service import effective_product_price
from app.modules.pedeon.application.public_schemas import PublicModifierOptionRead


class PedeOnPublicCatalogRuleTests(unittest.TestCase):
    def test_online_price_has_priority_over_product_offer(self):
        product = SimpleNamespace(sale_price=Decimal("12.00"), offer_price=Decimal("8.00"), offer_start_at=None, offer_end_at=None)
        publication = SimpleNamespace(online_price=Decimal("9.50"), use_product_offer=True)
        price, on_offer = effective_product_price(product, publication)
        self.assertEqual(price, Decimal("9.50"))
        self.assertFalse(on_offer)

    def test_active_product_offer_is_used_when_enabled(self):
        now = datetime.now(timezone.utc)
        product = SimpleNamespace(sale_price=Decimal("12.00"), offer_price=Decimal("8.00"), offer_start_at=now - timedelta(minutes=1), offer_end_at=now + timedelta(minutes=1))
        publication = SimpleNamespace(online_price=None, use_product_offer=True)
        price, on_offer = effective_product_price(product, publication, now=now)
        self.assertEqual(price, Decimal("8.00"))
        self.assertTrue(on_offer)

    def test_expired_offer_falls_back_to_sale_price(self):
        now = datetime.now(timezone.utc)
        product = SimpleNamespace(sale_price=Decimal("12.00"), offer_price=Decimal("8.00"), offer_start_at=now - timedelta(days=2), offer_end_at=now - timedelta(days=1))
        publication = SimpleNamespace(online_price=None, use_product_offer=True)
        price, on_offer = effective_product_price(product, publication, now=now)
        self.assertEqual(price, Decimal("12.00"))
        self.assertFalse(on_offer)

    def test_stock_product_can_be_used_as_option_without_publication(self):
        product = SimpleNamespace(
            sale_price=Decimal("7.50"),
            offer_price=None,
            offer_start_at=None,
            offer_end_at=None,
        )
        price, on_offer = effective_product_price(product, None)
        self.assertEqual(price, Decimal("7.50"))
        self.assertFalse(on_offer)

    def test_linked_option_exposes_available_stock_to_storefront(self):
        option = PublicModifierOptionRead(
            id=10,
            name="Coca-Cola",
            price_delta=Decimal("8.00"),
            available_quantity=3,
        )
        self.assertEqual(option.available_quantity, 3)


if __name__ == "__main__":
    unittest.main()

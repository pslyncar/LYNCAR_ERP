import unittest
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from app.modules.pedeon.application.delivery_service import PedeOnDeliveryService


class _ScalarResult:
    def __init__(self, values):
        self._values = values

    def all(self):
        return self._values


class _FakeDb:
    def __init__(self, zones):
        self._zones = zones

    def scalars(self, _query):
        return _ScalarResult(self._zones)


def _address(postal_code="17012-900", neighborhood="Centro"):
    return SimpleNamespace(
        postal_code=postal_code,
        neighborhood=neighborhood,
        city="Bauru",
        state="SP",
    )


def _zone(**values):
    defaults = {
        "postal_code_prefix": None,
        "neighborhood": None,
        "city": None,
        "state": None,
        "free_delivery_threshold": None,
        "estimated_minutes_min": None,
        "estimated_minutes_max": None,
        "center_latitude": None,
        "center_longitude": None,
        "radius_km": None,
    }
    return SimpleNamespace(**(defaults | values))


class DeliveryServiceTests(unittest.TestCase):
    def test_most_specific_postal_prefix_wins_and_can_be_free(self):
        broad = _zone(
            id=1,
            store_id=1,
            name="Bauru",
            match_type="postal_code_prefix",
            postal_code_prefix="170",
            fee_amount=Decimal("10"),
            minimum_order_amount=Decimal("0"),
            sort_order=0,
            active=True,
        )
        specific = _zone(
            id=2,
            store_id=1,
            name="Centro",
            match_type="postal_code_prefix",
            postal_code_prefix="17012",
            fee_amount=Decimal("6"),
            minimum_order_amount=Decimal("20"),
            free_delivery_threshold=Decimal("50"),
            estimated_minutes_min=30,
            estimated_minutes_max=45,
            sort_order=10,
            active=True,
        )
        service = PedeOnDeliveryService(_FakeDb([broad, specific]))

        quote = service.quote(SimpleNamespace(id=1, settings={}), _address(), Decimal("52"))

        self.assertEqual(quote.zone_id, 2)
        self.assertEqual(quote.fee, Decimal("0.00"))
        self.assertEqual(quote.estimated_minutes_max, 80)

    def test_neighborhood_matching_ignores_case_and_accents(self):
        zone = _zone(
            id=3,
            store_id=1,
            name="Jardim América",
            match_type="neighborhood",
            neighborhood="Jardim América",
            city="Bauru",
            state="SP",
            fee_amount=Decimal("7.50"),
            minimum_order_amount=Decimal("0"),
            sort_order=0,
            active=True,
        )
        service = PedeOnDeliveryService(_FakeDb([zone]))

        quote = service.quote(
            SimpleNamespace(id=1, settings={}),
            _address(neighborhood="JARDIM AMERICA"),
            Decimal("25"),
        )

        self.assertEqual(quote.zone_name, "Jardim América")
        self.assertEqual(quote.fee, Decimal("7.50"))

    def test_configured_zones_reject_unserved_address(self):
        zone = _zone(
            id=4,
            store_id=1,
            name="Centro",
            match_type="neighborhood",
            neighborhood="Centro",
            fee_amount=Decimal("5"),
            minimum_order_amount=Decimal("0"),
            sort_order=0,
            active=True,
        )
        service = PedeOnDeliveryService(_FakeDb([zone]))

        with self.assertRaisesRegex(ValueError, "não entregamos"):
            service.quote(
                SimpleNamespace(id=1, settings={}),
                _address(neighborhood="Vila Nova"),
                Decimal("25"),
            )

    def test_fixed_fee_does_not_require_a_zone(self):
        service = PedeOnDeliveryService(_FakeDb([]))
        store = SimpleNamespace(
            id=1,
            settings={"delivery_operation": {
                "pricing_mode": "fixed",
                "fixed_fee_amount": "8.50",
                "fixed_minimum_order_amount": "20",
                "preparation_minutes_min": 25,
                "preparation_minutes_max": 40,
            }},
        )
        quote = service.quote(store, _address(), Decimal("30"))
        self.assertEqual(quote.fee, Decimal("8.50"))
        self.assertEqual(quote.zone_name, "Taxa fixa")
        self.assertEqual(quote.estimated_minutes_min, 25)

    @patch(
        "app.modules.pedeon.application.delivery_service._postal_coordinates",
        return_value=(-22.31472, -49.06056),
    )
    def test_radius_accepts_address_inside_circle(self, _coordinates):
        zone = _zone(
            id=5,
            store_id=1,
            name="Raio central",
            match_type="radius",
            center_latitude=Decimal("-22.31472"),
            center_longitude=Decimal("-49.06056"),
            radius_km=Decimal("3"),
            fee_amount=Decimal("6.50"),
            minimum_order_amount=Decimal("0"),
            sort_order=0,
            active=True,
        )
        service = PedeOnDeliveryService(_FakeDb([zone]))

        quote = service.quote(
            SimpleNamespace(id=1, settings={}), _address(), Decimal("25")
        )

        self.assertEqual(quote.zone_name, "Raio central")
        self.assertEqual(quote.fee, Decimal("6.50"))


if __name__ == "__main__":
    unittest.main()

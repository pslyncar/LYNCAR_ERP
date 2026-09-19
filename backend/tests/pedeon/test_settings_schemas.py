import unittest

from pydantic import ValidationError

from app.modules.pedeon.application.schemas import (
    CategoryReorder,
    FulfillmentStationInput,
    ManualPixUpdate,
    StoreSettingsUpdate,
    TerminalPermissionUpdate,
)
from app.modules.pedeon.domain.lifecycle import TerminalCapability


class PedeOnSettingsSchemaTests(unittest.TestCase):
    def test_inventory_policy_defaults_to_warn_and_allow(self):
        payload = StoreSettingsUpdate(**self._store_payload())

        self.assertEqual(payload.inventory_policy, "warn_allow")

    def test_inventory_policy_accepts_supported_modes(self):
        for policy in ("warn_allow", "strict_block", "untracked"):
            payload = StoreSettingsUpdate(
                **self._store_payload(), inventory_policy=policy
            )
            self.assertEqual(payload.inventory_policy, policy)

    def _store_payload(self, **overrides):
        payload = {
            "public_slug": "minha-loja",
            "display_name": "Minha loja",
            "fulfillment_options": ["pickup"],
        }
        payload.update(overrides)
        return payload

    def test_store_accepts_food_or_retail_experience(self):
        food = StoreSettingsUpdate(**self._store_payload())
        retail = StoreSettingsUpdate(
            **self._store_payload(
                experience_mode="retail",
                default_fulfillment_mode="picking",
            )
        )
        self.assertEqual(food.experience_mode, "food_service")
        self.assertEqual(retail.default_fulfillment_mode, "picking")

    def test_store_rejects_ambiguous_hybrid_experience(self):
        with self.assertRaises(ValidationError):
            StoreSettingsUpdate(
                **self._store_payload(experience_mode="hybrid")
            )

    def test_store_rejects_kitchen_as_retail_default(self):
        with self.assertRaises(ValidationError):
            StoreSettingsUpdate(
                **self._store_payload(
                    experience_mode="retail",
                    default_fulfillment_mode="preparation",
                )
            )

    def test_category_order_rejects_duplicate_ids(self):
        with self.assertRaises(ValidationError):
            CategoryReorder(category_ids=[1, 2, 1])

    def test_enabled_manual_pix_requires_key_and_recipient(self):
        with self.assertRaises(ValidationError):
            ManualPixUpdate(enabled=True)

    def test_disabled_manual_pix_can_be_empty(self):
        settings = ManualPixUpdate(enabled=False)
        self.assertFalse(settings.enabled)

    def test_enabled_terminal_always_receives_view_capability(self):
        settings = TerminalPermissionUpdate(
            enabled=True,
            capabilities=[TerminalCapability.ACCEPT],
        )
        self.assertIn(TerminalCapability.VIEW, settings.capabilities)

    def test_station_code_is_normalized_for_safe_routing(self):
        station = FulfillmentStationInput(
            name="Cozinha quente",
            code=" Cozinha Quente ",
            station_type="preparation",
        )
        self.assertEqual(station.code, "cozinha-quente")

    def test_station_rejects_unknown_operational_type(self):
        with self.assertRaises(ValidationError):
            FulfillmentStationInput(
                name="Caixa",
                code="caixa",
                station_type="cashier",
            )


if __name__ == "__main__":
    unittest.main()

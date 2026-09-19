import unittest
from types import SimpleNamespace

from pydantic import ValidationError

from app.modules.pedeon.application.catalog_service import _slugify
from app.modules.pedeon.application.public_catalog_service import (
    PedeOnPublicCatalogService,
)
from app.modules.pedeon.application.schemas import (
    ModifierGroupInput,
    ModifierOptionInput,
    PublicationUpdate,
)


class PedeOnCatalogRuleTests(unittest.TestCase):
    def test_category_slug_is_stable_and_url_safe(self):
        self.assertEqual(_slugify("Pães & Doces"), "paes-doces")

    def test_online_price_cannot_be_negative(self):
        with self.assertRaises(ValidationError):
            PublicationUpdate(online_price=-1)

    def test_product_can_override_store_operational_flow(self):
        publication = PublicationUpdate(
            fulfillment_mode="none",
            print_policy="disabled",
        )
        self.assertEqual(publication.fulfillment_mode, "none")
        self.assertEqual(publication.print_policy, "disabled")

    def test_product_channels_are_unique_and_station_is_normalized(self) -> None:
        publication = PublicationUpdate(
            enabled_channels=["pedeon_online", "onsite_qr", "onsite_qr"],
            production_station_code="Bar Principal",
        )
        self.assertEqual(
            publication.enabled_channels, ["pedeon_online", "onsite_qr"]
        )
        self.assertEqual(publication.production_station_code, "bar-principal")

    def test_modifier_group_rejects_minimum_above_maximum(self):
        with self.assertRaises(ValidationError):
            ModifierGroupInput(
                name="Bebidas",
                minimum_selections=2,
                maximum_selections=1,
                options=[ModifierOptionInput(name="Refrigerante")],
            )

    def test_optional_beverage_group_accepts_multiple_options(self):
        group = ModifierGroupInput(
            name="Quer adicionar uma bebida?",
            minimum_selections=0,
            maximum_selections=2,
            options=[
                ModifierOptionInput(name="Refrigerante", product_id=10),
                ModifierOptionInput(name="Suco", product_id=11),
            ],
        )
        self.assertEqual(group.maximum_selections, 2)
        self.assertEqual([item.product_id for item in group.options], [10, 11])

    def test_product_channels_keep_online_and_waiter_independent(self) -> None:
        publication = SimpleNamespace(
            availability_rules={"enabled_channels": ["onsite_waiter"]}
        )
        self.assertTrue(
            PedeOnPublicCatalogService._enabled_for(
                publication, {"onsite_waiter"}
            )
        )
        self.assertFalse(
            PedeOnPublicCatalogService._enabled_for(
                publication, {"pedeon_online"}
            )
        )

    def test_legacy_product_defaults_only_to_online_channel(self) -> None:
        publication = SimpleNamespace(availability_rules={})
        self.assertEqual(
            PedeOnPublicCatalogService._enabled_channels(publication),
            {"pedeon_online"},
        )

    def test_question_supports_observation_and_answer_quantity_limits(self) -> None:
        question = ModifierGroupInput(
            name="Ponto da carne",
            kind="observation",
            minimum_selections=1,
            maximum_selections=1,
            options=[
                ModifierOptionInput(
                    name="Ao ponto",
                    minimum_quantity=1,
                    maximum_quantity=1,
                )
            ],
        )
        self.assertEqual(question.kind, "observation")
        self.assertEqual(question.options[0].maximum_quantity, 1)

    def test_observation_cannot_link_stock_product(self) -> None:
        with self.assertRaises(ValidationError):
            ModifierGroupInput(
                name="Observação",
                kind="observation",
                options=[ModifierOptionInput(name="Bebida", product_id=10)],
            )


if __name__ == "__main__":
    unittest.main()

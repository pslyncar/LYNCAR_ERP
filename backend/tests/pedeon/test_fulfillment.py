import unittest

from app.modules.pedeon.domain.fulfillment import (
    default_fulfillment_for_experience,
    resolve_fulfillment_mode,
    resolve_print_policy,
)


class PedeOnFulfillmentTests(unittest.TestCase):
    def test_food_and_retail_have_distinct_defaults(self):
        self.assertEqual(default_fulfillment_for_experience("food_service"), "preparation")
        self.assertEqual(default_fulfillment_for_experience("retail"), "picking")

    def test_product_may_skip_kitchen_without_hybrid_store(self):
        self.assertEqual(resolve_fulfillment_mode("preparation", "none"), "none")
        self.assertEqual(resolve_fulfillment_mode("preparation", "inherit"), "preparation")

    def test_printing_is_only_automatic_when_explicitly_resolved(self):
        self.assertEqual(resolve_print_policy("manual", "inherit"), "manual")
        self.assertEqual(resolve_print_policy("manual", "automatic"), "automatic")


if __name__ == "__main__":
    unittest.main()

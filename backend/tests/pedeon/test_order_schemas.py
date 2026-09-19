import unittest
from types import SimpleNamespace

from pydantic import ValidationError

from app.modules.pedeon.application.public_schemas import PublicOrderCreate
from app.modules.pedeon.application.order_service import PedeOnPublicOrderService


class PedeOnOrderSchemaTests(unittest.TestCase):
    def test_delivery_requires_structured_address_at_service_boundary(self):
        payload = PublicOrderCreate.model_validate(
            {
                "idempotency_key": "checkout-1234567890",
                "items": [{"product_id": 1, "quantity": 1}],
                "customer_name": "Cliente",
                "customer_phone": "11999999999",
                "fulfillment_type": "delivery",
                "payment_method": "manual_pix",
            }
        )
        self.assertIsNone(payload.delivery_address)

    def test_short_idempotency_key_is_rejected(self):
        with self.assertRaises(ValidationError):
            PublicOrderCreate.model_validate(
                {
                    "idempotency_key": "short",
                    "items": [{"product_id": 1, "quantity": 1}],
                    "customer_name": "Cliente",
                    "customer_phone": "11999999999",
                    "fulfillment_type": "pickup",
                    "payment_method": "manual_pix",
                }
            )

    def test_card_terminal_is_restricted_to_delivery(self):
        store = SimpleNamespace(
            accepting_orders=True,
            fulfillment_options=["pickup", "delivery"],
        )
        pickup = PublicOrderCreate.model_validate(
            {
                "idempotency_key": "checkout-card-pickup-01",
                "items": [{"product_id": 1, "quantity": 1}],
                "customer_name": "Cliente",
                "customer_phone": "11999999999",
                "fulfillment_type": "pickup",
                "payment_method": "credit_card_on_delivery",
            }
        )

        with self.assertRaisesRegex(ValueError, "somente para entrega"):
            PedeOnPublicOrderService._validate_store(store, pickup)

    def test_card_terminal_accepts_structured_delivery(self):
        store = SimpleNamespace(
            accepting_orders=True,
            fulfillment_options=["pickup", "delivery"],
        )
        delivery = PublicOrderCreate.model_validate(
            {
                "idempotency_key": "checkout-card-delivery-01",
                "items": [{"product_id": 1, "quantity": 1}],
                "customer_name": "Cliente",
                "customer_phone": "11999999999",
                "fulfillment_type": "delivery",
                "payment_method": "debit_card_on_delivery",
                "delivery_address": {
                    "postal_code": "01001000",
                    "street": "Praça da Sé",
                    "number": "1",
                    "neighborhood": "Sé",
                    "city": "São Paulo",
                    "state": "SP",
                },
            }
        )

        PedeOnPublicOrderService._validate_store(store, delivery)


if __name__ == "__main__":
    unittest.main()

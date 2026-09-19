import unittest

from app.modules.pedeon.domain import (
    FulfillmentType,
    InvalidOrderTransition,
    InvalidPaymentTransition,
    OrderStatus,
    PaymentMethod,
    PaymentStatus,
    ensure_order_transition,
    ensure_payment_transition,
)


class PedeOnLifecycleTests(unittest.TestCase):
    def test_delivery_can_follow_the_complete_operational_flow(self) -> None:
        flow = [
            OrderStatus.AWAITING_ACCEPTANCE,
            OrderStatus.ACCEPTED,
            OrderStatus.IN_PREPARATION,
            OrderStatus.READY,
            OrderStatus.OUT_FOR_DELIVERY,
            OrderStatus.COMPLETED,
        ]
        current = OrderStatus.AWAITING_PAYMENT

        for target in flow:
            ensure_order_transition(
                current,
                target,
                fulfillment_type=FulfillmentType.DELIVERY,
            )
            current = target

    def test_pickup_cannot_be_marked_as_out_for_delivery(self) -> None:
        with self.assertRaises(InvalidOrderTransition):
            ensure_order_transition(
                OrderStatus.READY,
                OrderStatus.OUT_FOR_DELIVERY,
                fulfillment_type=FulfillmentType.PICKUP,
            )

    def test_terminal_state_cannot_return_to_operation(self) -> None:
        with self.assertRaises(InvalidOrderTransition):
            ensure_order_transition(
                OrderStatus.COMPLETED,
                OrderStatus.IN_PREPARATION,
                fulfillment_type=FulfillmentType.DELIVERY,
            )

    def test_manual_pix_requires_review_before_confirmation(self) -> None:
        with self.assertRaises(InvalidPaymentTransition):
            ensure_payment_transition(
                PaymentStatus.PENDING,
                PaymentStatus.CONFIRMED,
                payment_method=PaymentMethod.MANUAL_PIX,
            )

        ensure_payment_transition(
            PaymentStatus.PENDING,
            PaymentStatus.AWAITING_MANUAL_CONFIRMATION,
            payment_method=PaymentMethod.MANUAL_PIX,
        )
        ensure_payment_transition(
            PaymentStatus.AWAITING_MANUAL_CONFIRMATION,
            PaymentStatus.CONFIRMED,
            payment_method=PaymentMethod.MANUAL_PIX,
        )

    def test_infinitepay_does_not_use_manual_review_state(self) -> None:
        with self.assertRaises(InvalidPaymentTransition):
            ensure_payment_transition(
                PaymentStatus.PENDING,
                PaymentStatus.AWAITING_MANUAL_CONFIRMATION,
                payment_method=PaymentMethod.INFINITEPAY_PIX,
            )

        ensure_payment_transition(
            PaymentStatus.PENDING,
            PaymentStatus.CONFIRMED,
            payment_method=PaymentMethod.INFINITEPAY_PIX,
        )

    def test_repeated_transition_is_idempotent(self) -> None:
        ensure_order_transition(
            OrderStatus.ACCEPTED,
            OrderStatus.ACCEPTED,
            fulfillment_type=FulfillmentType.PICKUP,
        )
        ensure_payment_transition(
            PaymentStatus.CONFIRMED,
            PaymentStatus.CONFIRMED,
            payment_method=PaymentMethod.INFINITEPAY_PIX,
        )


if __name__ == "__main__":
    unittest.main()

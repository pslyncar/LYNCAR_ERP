"""Estados e transicoes centrais do PedeOn.

Este arquivo nao conhece FastAPI, SQLAlchemy, InfinitePay nem Flutter. Ele e a
fonte pura das regras de ciclo de vida e pode ser exercitado sem infraestrutura.
"""

from __future__ import annotations

from enum import StrEnum


class OrderStatus(StrEnum):
    AWAITING_PAYMENT = "awaiting_payment"
    AWAITING_ACCEPTANCE = "awaiting_acceptance"
    ACCEPTED = "accepted"
    IN_PREPARATION = "in_preparation"
    READY = "ready"
    OUT_FOR_DELIVERY = "out_for_delivery"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


class PaymentMethod(StrEnum):
    INFINITEPAY_PIX = "infinitepay_pix"
    MANUAL_PIX = "manual_pix"
    CASH_ON_DELIVERY = "cash_on_delivery"
    CARD_ON_DELIVERY = "card_on_delivery"
    CREDIT_CARD_ON_DELIVERY = "credit_card_on_delivery"
    DEBIT_CARD_ON_DELIVERY = "debit_card_on_delivery"
    PAY_AT_PICKUP = "pay_at_pickup"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    AWAITING_MANUAL_CONFIRMATION = "awaiting_manual_confirmation"
    CONFIRMED = "confirmed"
    FAILED = "failed"
    EXPIRED = "expired"
    PARTIALLY_REFUNDED = "partially_refunded"
    REFUNDED = "refunded"


class FulfillmentType(StrEnum):
    PICKUP = "pickup"
    DELIVERY = "delivery"
    DINE_IN = "dine_in"


class TerminalCapability(StrEnum):
    VIEW = "view"
    NOTIFY = "notify"
    ACCEPT = "accept"
    PREPARE = "prepare"
    DISPATCH = "dispatch"
    CANCEL = "cancel"
    PRINT = "print"
    CHECKOUT = "checkout"
    PRIMARY_RECEIVER = "primary_receiver"
    BACKUP_RECEIVER = "backup_receiver"


class InvalidOrderTransition(ValueError):
    """A mudanca solicitada violaria o ciclo de vida do pedido."""


class InvalidPaymentTransition(ValueError):
    """A mudanca solicitada violaria o ciclo de vida do pagamento."""


_ORDER_TRANSITIONS: dict[OrderStatus, frozenset[OrderStatus]] = {
    OrderStatus.AWAITING_PAYMENT: frozenset(
        {
            OrderStatus.AWAITING_ACCEPTANCE,
            OrderStatus.CANCELLED,
            OrderStatus.EXPIRED,
        }
    ),
    OrderStatus.AWAITING_ACCEPTANCE: frozenset(
        {
            OrderStatus.ACCEPTED,
            OrderStatus.CANCELLED,
            OrderStatus.EXPIRED,
        }
    ),
    OrderStatus.ACCEPTED: frozenset(
        {
            OrderStatus.IN_PREPARATION,
            OrderStatus.READY,
            OrderStatus.CANCELLED,
        }
    ),
    OrderStatus.IN_PREPARATION: frozenset(
        {
            OrderStatus.READY,
            OrderStatus.CANCELLED,
        }
    ),
    OrderStatus.READY: frozenset(
        {
            OrderStatus.OUT_FOR_DELIVERY,
            OrderStatus.COMPLETED,
            OrderStatus.CANCELLED,
        }
    ),
    OrderStatus.OUT_FOR_DELIVERY: frozenset(
        {
            OrderStatus.COMPLETED,
            OrderStatus.CANCELLED,
        }
    ),
    OrderStatus.COMPLETED: frozenset(),
    OrderStatus.CANCELLED: frozenset(),
    OrderStatus.EXPIRED: frozenset(),
}


_PAYMENT_TRANSITIONS: dict[PaymentStatus, frozenset[PaymentStatus]] = {
    PaymentStatus.PENDING: frozenset(
        {
            PaymentStatus.AWAITING_MANUAL_CONFIRMATION,
            PaymentStatus.CONFIRMED,
            PaymentStatus.FAILED,
            PaymentStatus.EXPIRED,
        }
    ),
    PaymentStatus.AWAITING_MANUAL_CONFIRMATION: frozenset(
        {
            PaymentStatus.CONFIRMED,
            PaymentStatus.FAILED,
            PaymentStatus.EXPIRED,
        }
    ),
    PaymentStatus.CONFIRMED: frozenset(
        {
            PaymentStatus.PARTIALLY_REFUNDED,
            PaymentStatus.REFUNDED,
        }
    ),
    PaymentStatus.PARTIALLY_REFUNDED: frozenset({PaymentStatus.REFUNDED}),
    PaymentStatus.FAILED: frozenset(),
    PaymentStatus.EXPIRED: frozenset(),
    PaymentStatus.REFUNDED: frozenset(),
}


def ensure_order_transition(
    current: OrderStatus,
    target: OrderStatus,
    *,
    fulfillment_type: FulfillmentType,
) -> None:
    """Valida uma transicao sem produzir efeitos colaterais.

    Pedidos para retirada nunca passam por ``out_for_delivery``. Repetir o
    mesmo estado e aceito como operacao idempotente.
    """

    if current == target:
        return
    if (
        target == OrderStatus.OUT_FOR_DELIVERY
        and fulfillment_type != FulfillmentType.DELIVERY
    ):
        raise InvalidOrderTransition(
            "Pedido para retirada nao pode sair para entrega."
        )
    if target not in _ORDER_TRANSITIONS[current]:
        raise InvalidOrderTransition(
            f"Transicao de pedido invalida: {current.value} -> {target.value}."
        )


def ensure_payment_transition(
    current: PaymentStatus,
    target: PaymentStatus,
    *,
    payment_method: PaymentMethod,
) -> None:
    """Valida o ciclo do pagamento, inclusive a confirmacao do Pix manual."""

    if current == target:
        return
    if (
        payment_method == PaymentMethod.MANUAL_PIX
        and current == PaymentStatus.PENDING
        and target == PaymentStatus.CONFIRMED
    ):
        raise InvalidPaymentTransition(
            "Pix manual exige conferencia antes da confirmacao."
        )
    if (
        payment_method != PaymentMethod.MANUAL_PIX
        and target == PaymentStatus.AWAITING_MANUAL_CONFIRMATION
    ):
        raise InvalidPaymentTransition(
            "Somente Pix manual pode aguardar conferencia do estabelecimento."
        )
    if target not in _PAYMENT_TRANSITIONS[current]:
        raise InvalidPaymentTransition(
            f"Transicao de pagamento invalida: {current.value} -> {target.value}."
        )

"""Regras de negocio puras do PedeOn."""

from .lifecycle import (
    FulfillmentType,
    InvalidOrderTransition,
    InvalidPaymentTransition,
    OrderStatus,
    PaymentMethod,
    PaymentStatus,
    TerminalCapability,
    ensure_order_transition,
    ensure_payment_transition,
)

__all__ = [
    "FulfillmentType",
    "InvalidOrderTransition",
    "InvalidPaymentTransition",
    "OrderStatus",
    "PaymentMethod",
    "PaymentStatus",
    "TerminalCapability",
    "ensure_order_transition",
    "ensure_payment_transition",
]

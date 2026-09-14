"""Modelos persistentes do PedeOn.

Os imports abaixo registram todas as tabelas no metadata compartilhado do
tenant sem colocar os modelos em um unico arquivo.
"""

from .events import PedeOnOrderEvent, PedeOnOutboxEvent
from .edge import PedeOnEdgeNode
from .operations import (
    PedeOnDeliveryZone,
    PedeOnFulfillmentStation,
    PedeOnFulfillmentTask,
    PedeOnPrintJob,
    PedeOnStockReservation,
    PedeOnTerminalPermission,
)
from .order import PedeOnOrder, PedeOnOrderItem, PedeOnOrderItemModifier
from .customer import PedeOnCustomer
from .payment import PedeOnPaymentConfiguration, PedeOnPaymentTransaction
from .store import (
    PedeOnCategory,
    PedeOnModifierGroup,
    PedeOnModifierOption,
    PedeOnProductModifierGroup,
    PedeOnProductPublication,
    PedeOnStore,
)

__all__ = [
    "PedeOnCategory",
    "PedeOnCustomer",
    "PedeOnDeliveryZone",
    "PedeOnEdgeNode",
    "PedeOnFulfillmentStation",
    "PedeOnFulfillmentTask",
    "PedeOnModifierGroup",
    "PedeOnModifierOption",
    "PedeOnOrder",
    "PedeOnOrderEvent",
    "PedeOnOrderItem",
    "PedeOnOrderItemModifier",
    "PedeOnOutboxEvent",
    "PedeOnPaymentConfiguration",
    "PedeOnPaymentTransaction",
    "PedeOnPrintJob",
    "PedeOnProductModifierGroup",
    "PedeOnProductPublication",
    "PedeOnStockReservation",
    "PedeOnStore",
    "PedeOnTerminalPermission",
]

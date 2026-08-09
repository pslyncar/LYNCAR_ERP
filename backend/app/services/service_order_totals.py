from decimal import Decimal

from app.models.service_order import ServiceOrder


def recalculate_service_order_totals(service_order: ServiceOrder) -> None:
    items_amount = sum((item.total_price for item in service_order.items), Decimal("0"))
    service_order.items_amount = items_amount
    service_order.total_amount = (
        service_order.labor_amount + items_amount - service_order.discount_amount
    )
    if service_order.total_amount < 0:
        service_order.total_amount = Decimal("0")

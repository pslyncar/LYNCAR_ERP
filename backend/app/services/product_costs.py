from decimal import Decimal

from app.models.product import Product


def _legacy_base_unit_cost(product: Product) -> Decimal | None:
    quantity = product.purchase_quantity or product.stock_quantity
    if product.purchase_total_cost is None or quantity <= 0:
        return None
    return product.purchase_total_cost / quantity


def current_unit_cost(product: Product) -> Decimal | None:
    if product.average_cost is not None and product.average_cost >= 0:
        return product.average_cost
    return _legacy_base_unit_cost(product)


def base_unit_cost(product: Product) -> Decimal | None:
    return current_unit_cost(product)


def refresh_inventory_value(product: Product, *, force_from_purchase: bool = False) -> None:
    unit_cost = (
        _legacy_base_unit_cost(product)
        if force_from_purchase
        else current_unit_cost(product)
    ) or Decimal("0")
    product.average_cost = unit_cost
    product.stock_value = product.stock_quantity * unit_cost


def apply_stock_in(product: Product, quantity: Decimal, total_cost: Decimal | None) -> tuple[Decimal | None, Decimal | None]:
    current_cost = current_unit_cost(product)
    previous_value = product.stock_value or (product.stock_quantity * (current_cost or Decimal("0")))
    effective_total_cost = total_cost
    if effective_total_cost is None and current_cost is not None:
        effective_total_cost = quantity * current_cost

    product.stock_quantity += quantity
    if effective_total_cost is not None:
        product.stock_value = previous_value + effective_total_cost
        product.average_cost = (
            product.stock_value / product.stock_quantity
            if product.stock_quantity > 0
            else Decimal("0")
        )
    else:
        refresh_inventory_value(product)

    return product.average_cost, effective_total_cost


def apply_stock_out(product: Product, quantity: Decimal) -> tuple[Decimal | None, Decimal | None]:
    unit_cost = current_unit_cost(product)
    total_cost = quantity * unit_cost if unit_cost is not None else None
    product.stock_quantity -= quantity
    if unit_cost is not None:
        product.stock_value = product.stock_quantity * unit_cost
    else:
        product.stock_value = Decimal("0")
    return unit_cost, total_cost

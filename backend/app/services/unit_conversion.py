from decimal import Decimal


UNIT_FACTORS = {
    "kg": ("mass", Decimal("1000")),
    "g": ("mass", Decimal("1")),
    "t": ("mass", Decimal("1000000")),
    "l": ("volume", Decimal("1000")),
    "ml": ("volume", Decimal("1")),
    "m": ("length", Decimal("1000")),
    "cm": ("length", Decimal("10")),
    "mm": ("length", Decimal("1")),
    "m2": ("area", Decimal("1")),
    "m3": ("volume3", Decimal("1")),
}


def are_units_compatible(from_unit: str, to_unit: str) -> bool:
    normalized_from = from_unit.strip().lower()
    normalized_to = to_unit.strip().lower()
    if normalized_from == normalized_to:
        return True
    from_data = UNIT_FACTORS.get(normalized_from)
    to_data = UNIT_FACTORS.get(normalized_to)
    return from_data is not None and to_data is not None and from_data[0] == to_data[0]


def convert_quantity(quantity: Decimal, from_unit: str, to_unit: str) -> Decimal:
    normalized_from = from_unit.strip().lower()
    normalized_to = to_unit.strip().lower()
    if normalized_from == normalized_to:
        return quantity

    from_data = UNIT_FACTORS.get(normalized_from)
    to_data = UNIT_FACTORS.get(normalized_to)
    if from_data is None or to_data is None or from_data[0] != to_data[0]:
        raise ValueError(f"Unidades incompativeis: {from_unit} para {to_unit}.")

    return quantity * from_data[1] / to_data[1]

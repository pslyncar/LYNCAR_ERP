from decimal import Decimal
from types import SimpleNamespace

from app.api.routes.cash_closings import (
    _expected_cash_after_float_return,
    _movement_total,
    _payment_totals_for_sales,
    money,
)
from app.schemas.cash_closing import CashClosingCreate, CashClosingMovementCreate


def test_payment_totals_subtract_change_from_cash_only() -> None:
    sales = [
        SimpleNamespace(
            change_amount=Decimal("7.80"),
            payments=[
                SimpleNamespace(method="dinheiro", amount=Decimal("10.00")),
                SimpleNamespace(method="pix", amount=Decimal("5.24")),
            ],
        )
    ]

    totals = _payment_totals_for_sales(sales)

    assert totals["dinheiro"] == Decimal("2.20")
    assert totals["pix"] == Decimal("5.24")


def test_payment_totals_can_apply_change_across_cash_payments() -> None:
    sales = [
        SimpleNamespace(
            change_amount=Decimal("7.00"),
            payments=[
                SimpleNamespace(method="dinheiro", amount=Decimal("5.00")),
                SimpleNamespace(method="dinheiro", amount=Decimal("10.00")),
            ],
        )
    ]

    totals = _payment_totals_for_sales(sales)

    assert totals["dinheiro"] == Decimal("8.00")


def test_movement_total_filters_by_type() -> None:
    closing = CashClosingCreate(
        counted_cash_amount=Decimal("0"),
        movements=[
            CashClosingMovementCreate(movement_type="sangria", amount=Decimal("3.00")),
            CashClosingMovementCreate(movement_type="suprimento", amount=Decimal("2.50")),
            CashClosingMovementCreate(movement_type="sangria", amount=Decimal("1.75")),
        ],
    )

    assert _movement_total(closing, "sangria") == Decimal("4.75")
    assert _movement_total(closing, "suprimento") == Decimal("2.50")


def test_money_rounds_to_cents() -> None:
    assert money(Decimal("1.005")) == Decimal("1.01")


def test_expected_cash_does_not_count_opening_float() -> None:
    assert _expected_cash_after_float_return(
        Decimal("5.00"), Decimal("0"), Decimal("0")
    ) == Decimal("5.00")


def test_expected_cash_applies_supplies_and_withdrawals() -> None:
    assert _expected_cash_after_float_return(
        Decimal("25.00"), Decimal("10.00"), Decimal("7.50")
    ) == Decimal("27.50")


def test_expected_cash_never_becomes_negative() -> None:
    assert _expected_cash_after_float_return(
        Decimal("5.00"), Decimal("0"), Decimal("20.00")
    ) == Decimal("0.00")

from decimal import Decimal
import unittest

from app.services.nfe_sp import _allocate_line_amounts, _duplicate_nfe_key


class NfeTotalsTest(unittest.TestCase):
    def test_allocation_closes_exactly_with_rounding(self) -> None:
        allocated = _allocate_line_amounts(
            Decimal("10.00"),
            [Decimal("1"), Decimal("1"), Decimal("1")],
        )

        self.assertEqual(sum(allocated), Decimal("10.00"))
        self.assertEqual(allocated, [Decimal("3.34"), Decimal("3.33"), Decimal("3.33")])

    def test_zero_value_items_share_fiscal_additions(self) -> None:
        allocated = _allocate_line_amounts(
            Decimal("25.50"),
            [Decimal("0"), Decimal("0")],
        )

        self.assertEqual(allocated, [Decimal("12.75"), Decimal("12.75")])

    def test_single_item_receives_full_amount(self) -> None:
        self.assertEqual(
            _allocate_line_amounts(Decimal("2.75"), [Decimal("0")]),
            [Decimal("2.75")],
        )

    def test_extracts_duplicate_key_from_sefaz_message(self) -> None:
        key = "35260763816719000115550010000000111936238587"

        self.assertEqual(
            _duplicate_nfe_key(
                f"Duplicidade de NF-e com diferenca na Chave de Acesso [chNFe:{key}]"
            ),
            key,
        )


if __name__ == "__main__":
    unittest.main()

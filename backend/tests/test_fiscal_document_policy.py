from types import SimpleNamespace
import unittest

from app.services.fiscal_document_policy import (
    choose_fiscal_document_policy,
    should_move_stock_for_fiscal_document,
)


class FiscalDocumentPolicyTests(unittest.TestCase):
    def test_consumer_same_state_prefers_nfce(self) -> None:
        setting = SimpleNamespace(uf="SP")
        client = SimpleNamespace(state="SP", state_registration=None, tax_contributor_type=None)

        policy = choose_fiscal_document_policy(setting, client)

        self.assertEqual(policy.model, "65")
        self.assertEqual(policy.document_type, "nfce")

    def test_icms_taxpayer_uses_nfe(self) -> None:
        setting = SimpleNamespace(uf="SP")
        client = SimpleNamespace(state="SP", state_registration="123", tax_contributor_type="1")

        policy = choose_fiscal_document_policy(setting, client)

        self.assertEqual(policy.model, "55")
        self.assertEqual(policy.document_type, "nfe")

    def test_interstate_sale_uses_nfe(self) -> None:
        setting = SimpleNamespace(uf="SP")
        client = SimpleNamespace(state="RJ", state_registration=None, tax_contributor_type=None)

        policy = choose_fiscal_document_policy(setting, client)

        self.assertEqual(policy.model, "55")
        self.assertEqual(policy.document_type, "nfe")

    def test_sale_based_document_never_moves_stock_again(self) -> None:
        document = SimpleNamespace(
            sale_id=123,
            stock_deduction_on_authorize=False,
        )

        self.assertFalse(should_move_stock_for_fiscal_document(document))

    def test_only_explicit_manual_document_moves_stock(self) -> None:
        document = SimpleNamespace(
            sale_id=None,
            stock_deduction_on_authorize=True,
        )

        self.assertTrue(should_move_stock_for_fiscal_document(document))


if __name__ == "__main__":
    unittest.main()

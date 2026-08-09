from types import SimpleNamespace
import unittest

from app.services.fiscal_document_policy import choose_fiscal_document_policy


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


if __name__ == "__main__":
    unittest.main()

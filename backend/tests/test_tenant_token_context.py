import unittest
from unittest.mock import Mock, patch

from app.services.tenancy import company_code_from_token_claims, company_from_token_claims


class TenantTokenContextTest(unittest.TestCase):
    @patch("app.services.tenancy.require_active_company_by_id")
    def test_prefers_stable_company_id_over_legacy_code(self, require_by_id: Mock) -> None:
        company = Mock(code="padariadrika")
        require_by_id.return_value = company

        resolved = company_from_token_claims(
            {"company_id": 42, "company_code": "old-company-code"}
        )

        self.assertIs(resolved, company)
        self.assertEqual(company_code_from_token_claims({"company_id": 42}), "padariadrika")
        require_by_id.assert_called_with(42)

    @patch("app.services.tenancy.require_active_company")
    def test_legacy_tokens_still_resolve_by_company_code(self, require_by_code: Mock) -> None:
        require_by_code.return_value = Mock(code="Padaria-Drika")

        self.assertEqual(
            company_code_from_token_claims({"company_code": "PADARIA-DRIKA"}),
            "padaria-drika",
        )
        require_by_code.assert_called_once_with("PADARIA-DRIKA")

    def test_missing_context_is_rejected(self) -> None:
        with self.assertRaises(LookupError):
            company_from_token_claims({})


if __name__ == "__main__":
    unittest.main()

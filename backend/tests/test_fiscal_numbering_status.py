import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app.api.routes.fiscal import get_fiscal_numbering_status, sync_nfce_numbering
from app.services.nfce_listagem_chaves_sp import NfceNumberSyncResult


class _ScalarDb:
    def __init__(self, values):
        self._values = iter(values)

    def scalar(self, statement):
        return next(self._values)

    def commit(self):
        return None


class FiscalNumberingStatusTests(unittest.TestCase):
    def test_reports_last_authorized_and_next_number_for_both_models(self):
        setting = SimpleNamespace(
            environment="homologacao",
            nfce_series=1,
            nfce_next_number=72,
            nfce_last_authorized_number=69,
            nfe_series=1,
            nfe_next_number=13,
            nfe_last_authorized_number=12,
        )
        db = _ScalarDb([71, 12])

        with patch(
            "app.api.routes.fiscal._get_or_create_settings",
            return_value=setting,
        ):
            result = get_fiscal_numbering_status(
                db=db,
                current_user=SimpleNamespace(),
            )

        self.assertEqual(result.nfce_last_authorized_number, 71)
        self.assertEqual(result.nfce_next_number, 72)
        self.assertEqual(result.nfe_last_authorized_number, 12)
        self.assertEqual(result.nfe_next_number, 13)

    def test_sync_is_available_in_production(self):
        setting = SimpleNamespace(
            environment="producao",
            nfce_next_number=72,
            nfce_last_authorized_number=69,
        )
        sync_result = NfceNumberSyncResult(
            environment="producao",
            series=1,
            current_next_number=72,
            highest_authorized_number=71,
            suggested_next_number=72,
            updated_next_number=72,
            keys_count=71,
            incomplete=False,
            status_code="100",
            message="ok",
        )

        with (
            patch(
                "app.api.routes.fiscal._get_or_create_settings",
                return_value=setting,
            ),
            patch(
                "app.api.routes.fiscal.sync_nfce_next_number_from_sefaz",
                return_value=sync_result,
            ),
        ):
            result = sync_nfce_numbering(
                db=_ScalarDb([]),
                current_user=SimpleNamespace(),
            )

        self.assertEqual(result.environment, "producao")
        self.assertEqual(result.highest_authorized_number, 71)


if __name__ == "__main__":
    unittest.main()

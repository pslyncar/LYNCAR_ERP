import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app.api.routes.fiscal import get_fiscal_numbering_status


class _ScalarDb:
    def __init__(self, values):
        self._values = iter(values)

    def scalar(self, statement):
        return next(self._values)


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


if __name__ == "__main__":
    unittest.main()

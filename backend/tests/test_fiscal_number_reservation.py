import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock

from app.api.routes.fiscal import (
    _next_available_fiscal_number,
    _reserve_fiscal_number,
)


class FiscalNumberReservationTests(unittest.TestCase):
    def test_rejected_number_is_skipped_without_releasing_its_ownership(self) -> None:
        rejected_owner = SimpleNamespace(id=10, status="rejected")
        db = MagicMock()
        db.scalar.side_effect = [74, rejected_owner, None]

        number = _next_available_fiscal_number(
            db,
            environment="homologacao",
            document_type="nfce",
            series=1,
            configured_next_number=75,
        )

        self.assertEqual(number, 76)

    def test_reservation_does_not_advance_sequence_before_authorization(self) -> None:
        document = SimpleNamespace(
            id=20,
            document_type="nfce",
            environment="homologacao",
            series=None,
            number=None,
            status="draft",
            updated_at=None,
            sefaz_status_code=None,
            sefaz_message=None,
        )
        setting = SimpleNamespace(
            nfce_series=1,
            nfce_next_number=75,
            nfe_series=1,
            nfe_next_number=1,
        )
        db = MagicMock()
        db.scalar.side_effect = [document, setting, 74, None]

        reserved, locked_setting = _reserve_fiscal_number(db, document.id)

        self.assertIs(reserved, document)
        self.assertIs(locked_setting, setting)
        self.assertEqual(document.number, 75)
        self.assertEqual(document.status, "processing")
        self.assertEqual(setting.nfce_next_number, 75)
        db.flush.assert_called_once()
        db.commit.assert_not_called()

    def test_retry_reuses_the_same_rejected_number(self) -> None:
        document = SimpleNamespace(
            id=21,
            document_type="nfce",
            environment="homologacao",
            series=1,
            number=75,
            status="rejected",
            updated_at=None,
            sefaz_status_code="225",
            sefaz_message="rejeitada",
        )
        setting = SimpleNamespace(
            nfce_series=1,
            nfce_next_number=75,
            nfe_series=1,
            nfe_next_number=1,
        )
        db = MagicMock()
        db.scalar.side_effect = [document, setting]

        reserved, _ = _reserve_fiscal_number(db, document.id)

        self.assertEqual(reserved.number, 75)
        self.assertEqual(setting.nfce_next_number, 75)
        db.commit.assert_not_called()


if __name__ == "__main__":
    unittest.main()

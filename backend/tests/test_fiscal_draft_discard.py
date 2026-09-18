import unittest
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.api.routes.fiscal import (
    _can_discard_unnumbered_fiscal_draft,
    discard_unnumbered_fiscal_draft,
)
from app.core.database import Base
from app.migrate_local import fiscal as _fiscal_models  # noqa: F401
from app.models.fiscal import FiscalDocument, FiscalDocumentSale
from app.models.sale import Sale


class FiscalDraftDiscardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite+pysqlite:///:memory:")
        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _draft(self, **overrides):
        data = {
            "status": "draft",
            "number": None,
            "series": None,
            "access_key": None,
            "xml_generated": None,
            "xml_signed": None,
            "xml_authorized": None,
            "sefaz_protocol": None,
            "issued_at": None,
            "authorized_at": None,
            "cancelled_at": None,
        }
        data.update(overrides)
        return SimpleNamespace(**data)

    def test_only_unnumbered_and_untransmitted_draft_is_discardable(self) -> None:
        self.assertTrue(_can_discard_unnumbered_fiscal_draft(self._draft()))
        self.assertFalse(
            _can_discard_unnumbered_fiscal_draft(self._draft(number=42, series=1))
        )
        self.assertFalse(
            _can_discard_unnumbered_fiscal_draft(self._draft(status="rejected"))
        )
        self.assertFalse(
            _can_discard_unnumbered_fiscal_draft(
                self._draft(xml_signed="<NFe>assinada</NFe>")
            )
        )

    def test_discarding_finance_draft_keeps_sales_and_removes_fiscal_link(self) -> None:
        sale = Sale(number="V100", status="finalizada")
        document = FiscalDocument(
            document_type="nfe",
            model="55",
            environment="homologacao",
            status="draft",
        )
        self.db.add_all([sale, document])
        self.db.flush()
        self.db.add(FiscalDocumentSale(fiscal_document_id=document.id, sale_id=sale.id))
        self.db.commit()

        response = discard_unnumbered_fiscal_draft(
            document.id,
            self.db,
            SimpleNamespace(id=1),
        )

        self.assertEqual(response.status_code, 204)
        self.assertIsNone(self.db.get(FiscalDocument, document.id))
        self.assertEqual(self.db.query(FiscalDocumentSale).count(), 0)
        self.assertIsNotNone(self.db.get(Sale, sale.id))


if __name__ == "__main__":
    unittest.main()

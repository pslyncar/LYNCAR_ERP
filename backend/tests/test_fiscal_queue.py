import unittest

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.core.database import Base
from app.migrate_local import fiscal as _fiscal_models  # noqa: F401
from app.models.fiscal import FiscalDocument, FiscalTransmissionJob
from app.services.fiscal_queue import (
    enqueue_fiscal_job,
    fiscal_lane_key,
    resume_fiscal_configuration_jobs,
)


class FiscalQueueTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite+pysqlite:///:memory:")
        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _document(self, *, number: int = 75) -> FiscalDocument:
        document = FiscalDocument(
            document_type="nfce",
            model="65",
            series=1,
            number=number,
            environment="homologacao",
            status="draft",
        )
        self.db.add(document)
        self.db.commit()
        return document

    def test_enqueue_is_idempotent_for_document_and_job_type(self) -> None:
        document = self._document()

        first = enqueue_fiscal_job(
            self.db,
            document,
            requested_by_user_id=None,
        )
        self.db.commit()
        second = enqueue_fiscal_job(
            self.db,
            document,
            requested_by_user_id=None,
        )
        self.db.commit()

        self.assertEqual(first.id, second.id)
        self.assertEqual(
            self.db.query(FiscalTransmissionJob).count(),
            1,
        )

    def test_lane_separates_environment_model_and_series(self) -> None:
        document = self._document(number=80)

        self.assertEqual(
            fiscal_lane_key(document),
            "homologacao:nfce:1",
        )

    def test_reenqueue_unblocks_a_corrected_document(self) -> None:
        document = self._document(number=81)
        job = enqueue_fiscal_job(
            self.db,
            document,
            requested_by_user_id=None,
        )
        job.status = "blocked"
        job.last_error = "NCM invalido"
        self.db.commit()

        same_job = enqueue_fiscal_job(
            self.db,
            document,
            requested_by_user_id=None,
        )
        self.db.commit()

        self.assertEqual(job.id, same_job.id)
        self.assertEqual(same_job.status, "pending")
        self.assertIsNone(same_job.last_error)

    def test_configuration_change_requeues_waiting_document(self) -> None:
        document = self._document(number=82)
        document.status = "pending_configuration"
        document.sefaz_status_code = "CONFIGURACAO_FISCAL"
        document.sefaz_message = "Produto sem NCM"
        job = enqueue_fiscal_job(
            self.db,
            document,
            requested_by_user_id=None,
        )
        job.status = "blocked"
        self.db.commit()

        resumed = resume_fiscal_configuration_jobs(self.db)
        self.db.commit()

        self.assertEqual(resumed, 1)
        self.assertEqual(document.status, "draft")
        self.assertIsNone(document.sefaz_status_code)
        self.assertIsNone(document.sefaz_message)
        self.assertEqual(job.status, "pending")


if __name__ == "__main__":
    unittest.main()

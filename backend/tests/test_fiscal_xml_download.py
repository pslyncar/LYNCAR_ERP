from types import SimpleNamespace
import unittest

from fastapi import HTTPException

from app.api.routes.fiscal import (
    _fiscal_xml_filename,
    download_fiscal_document_xml,
)


class _FakeDb:
    def __init__(self, document) -> None:
        self.document = document

    def get(self, model, document_id: int):
        return self.document if self.document and self.document.id == document_id else None


class FiscalXmlDownloadTests(unittest.TestCase):
    def test_filename_identifies_model_series_and_number(self) -> None:
        document = SimpleNamespace(
            id=99,
            document_type="nfe",
            series=3,
            number=12,
        )

        self.assertEqual(
            _fiscal_xml_filename(document),
            "nfe-serie-3-numero-12.xml",
        )

    def test_filename_uses_safe_defaults(self) -> None:
        document = SimpleNamespace(
            id=42,
            document_type="unexpected",
            series=None,
            number=None,
        )

        self.assertEqual(
            _fiscal_xml_filename(document),
            "nfce-serie-1-numero-42.xml",
        )

    def test_download_returns_authorized_xml_as_attachment(self) -> None:
        document = SimpleNamespace(
            id=12,
            document_type="nfe",
            series=1,
            number=12,
            status="authorized",
            xml_authorized="<nfeProc>autorizada</nfeProc>",
        )

        response = download_fiscal_document_xml(
            document_id=12,
            db=_FakeDb(document),
            current_user=SimpleNamespace(id=1),
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.body, b"<nfeProc>autorizada</nfeProc>")
        self.assertEqual(response.media_type, "application/xml")
        self.assertEqual(
            response.headers["content-disposition"],
            'attachment; filename="nfe-serie-1-numero-12.xml"',
        )

    def test_download_rejects_document_without_authorized_xml(self) -> None:
        document = SimpleNamespace(
            id=7,
            document_type="nfce",
            series=1,
            number=7,
            status="authorized",
            xml_authorized=None,
        )

        with self.assertRaises(HTTPException) as raised:
            download_fiscal_document_xml(
                document_id=7,
                db=_FakeDb(document),
                current_user=SimpleNamespace(id=1),
            )

        self.assertEqual(raised.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()

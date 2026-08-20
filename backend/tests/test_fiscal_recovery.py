import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app.services.fiscal_recovery import recover_fiscal_documents


class FiscalRecoveryTests(unittest.TestCase):
    def test_does_not_download_nfce_xml_that_is_already_stored(self):
        key = "35" + "2" * 18 + "65" + "1" * 22
        setting = SimpleNamespace(environment="homologacao")

        with (
            patch(
                "app.services.fiscal_recovery.list_nfce_keys",
                return_value=([key], False, "100", "ok"),
            ),
            patch(
                "app.services.fiscal_recovery.download_nfce_xml"
            ) as download,
        ):
            result = recover_fiscal_documents(
                setting,
                existing_nfce_xml_keys={key},
            )

        self.assertEqual(result.nfce_keys, 1)
        self.assertEqual(result.nfce_existing, 1)
        self.assertEqual(result.nfce_downloaded, 0)
        download.assert_not_called()


if __name__ == "__main__":
    unittest.main()

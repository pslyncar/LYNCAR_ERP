import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app.api.routes.fiscal import recover_documents_from_sefaz
from app.services.fiscal_recovery import FiscalRecoveryResult, recover_fiscal_documents


class _RecoveryDb:
    def scalars(self, statement):
        return iter(())

    def commit(self):
        return None


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

    def test_route_is_available_in_production(self):
        setting = SimpleNamespace(
            environment="producao",
            nfce_next_number=72,
            nfe_next_number=13,
            nfce_last_authorized_number=69,
            nfe_last_authorized_number=12,
        )
        recovery = FiscalRecoveryResult(
            nfce_keys=0,
            nfce_existing=0,
            nfce_downloaded=0,
            nfe_docs=0,
            messages=("produção consultada",),
        )

        with (
            patch(
                "app.api.routes.fiscal._get_or_create_settings",
                return_value=setting,
            ),
            patch(
                "app.api.routes.fiscal.recover_fiscal_documents",
                return_value=recovery,
            ) as recover,
        ):
            result = recover_documents_from_sefaz(
                db=_RecoveryDb(),
                current_user=SimpleNamespace(),
            )

        self.assertEqual(result.nfce_keys, 0)
        recover.assert_called_once_with(setting, existing_nfce_xml_keys=set())


if __name__ == "__main__":
    unittest.main()

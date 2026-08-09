from datetime import date
from decimal import Decimal
from types import SimpleNamespace
import unittest

from app.services.rtc_compliance import (
    RTC_HOMOLOGATION_CRT3_MANDATORY_FROM,
    RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM,
    RtcComplianceError,
    is_rtc_mandatory,
    rtc_rates_for,
    validate_rtc_document,
)
from app.services.fiscal_output_rules import resolve_output_tax_profile


def setting(*, crt: str, tax_regime: str = "") -> SimpleNamespace:
    return SimpleNamespace(
        crt=crt,
        tax_regime=tax_regime,
        environment="producao",
        uf="SP",
        output_rules=[],
    )


def product(
    name: str,
    *,
    ncm: str | None = "19059090",
    cfop: str | None = "5102",
    rtc_cst: str | None = None,
    rtc_classification: str | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=1,
        name=name,
        ncm=ncm,
        cfop_sale=cfop,
        origin="0",
        cst="00",
        csosn=None,
        icms_rate=None,
        pis_rate=None,
        cofins_rate=None,
        ibs_cbs_cst=rtc_cst,
        ibs_cbs_classification=rtc_classification,
        cbs_rate=None,
        ibs_state_rate=None,
        ibs_city_rate=None,
        selective_tax_cst=None,
        selective_tax_classification=None,
        selective_tax_rate=None,
        tax_rules=[],
    )


def sale(*products: SimpleNamespace) -> SimpleNamespace:
    return SimpleNamespace(
        items=[SimpleNamespace(product=current) for current in products],
    )


class RtcComplianceTests(unittest.TestCase):
    def test_crt3_is_mandatory_in_homologation_from_official_date(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")
        issuer.environment = "homologacao"

        self.assertFalse(
            is_rtc_mandatory(
                issuer,
                RTC_HOMOLOGATION_CRT3_MANDATORY_FROM.replace(day=30, month=6),
            )
        )
        self.assertTrue(is_rtc_mandatory(issuer, RTC_HOMOLOGATION_CRT3_MANDATORY_FROM))

    def test_crt3_production_ub12_10_has_no_fixed_mandatory_date(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")

        self.assertFalse(is_rtc_mandatory(issuer, date(2026, 8, 9)))

    def test_mei_and_simples_are_not_promoted_to_crt3(self) -> None:
        issue_date = date(2026, 8, 8)

        self.assertFalse(is_rtc_mandatory(setting(crt="4", tax_regime="mei"), issue_date))
        self.assertFalse(
            is_rtc_mandatory(setting(crt="1", tax_regime="simples_nacional"), issue_date)
        )

    def test_mei_and_simples_become_mandatory_on_2027_date(self) -> None:
        self.assertTrue(
            is_rtc_mandatory(
                setting(crt="4", tax_regime="mei"),
                RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM,
            )
        )

    def test_mei_without_rtc_fields_passes_preflight(self) -> None:
        validate_rtc_document(
            setting(crt="4", tax_regime="mei"),
            sale(product("Produto MEI")),
            model="65",
            issue_date=date(2026, 8, 8),
        )

    def test_crt3_reports_all_incomplete_products_at_once(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")
        issuer.environment = "homologacao"
        with self.assertRaises(RtcComplianceError) as context:
            validate_rtc_document(
                issuer,
                sale(
                    product("Produto A", ncm="123", cfop=None),
                    product("Produto B", rtc_cst="00", rtc_classification="1"),
                ),
                model="65",
                issue_date=date(2026, 8, 8),
            )

        message = str(context.exception)
        self.assertIn("Produto A: NCM deve ter 8 dígitos", message)
        self.assertIn("Produto A: CST IBS/CBS deve ter 3 dígitos", message)
        self.assertIn("Produto B: CST IBS/CBS deve ter 3 dígitos", message)
        self.assertIn("Produto B: cClassTrib IBS/CBS deve ter 6 dígitos", message)

    def test_crt3_complete_product_passes_preflight(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")
        issuer.environment = "homologacao"
        validate_rtc_document(
            issuer,
            sale(
                product(
                    "Produto completo",
                    rtc_cst="000",
                    rtc_classification="000001",
                )
            ),
            model="55",
            issue_date=date(2026, 8, 8),
        )

    def test_2026_rates_are_centralized(self) -> None:
        rates = rtc_rates_for(date(2026, 8, 8))

        self.assertEqual(rates.cbs, Decimal("0.9000"))
        self.assertEqual(rates.ibs_uf, Decimal("0.1000"))
        self.assertEqual(rates.ibs_mun, Decimal("0.0000"))

    def test_output_cfop_defaults_follow_destination_uf(self) -> None:
        issuer = setting(crt="4", tax_regime="mei")
        current_product = product("Produto")

        same_state = resolve_output_tax_profile(
            issuer,
            current_product,
            model="55",
            uf_destination="SP",
        )
        other_state = resolve_output_tax_profile(
            issuer,
            current_product,
            model="55",
            uf_destination="RJ",
        )

        self.assertEqual(same_state.cfop, "5102")
        self.assertEqual(other_state.cfop, "6102")


if __name__ == "__main__":
    unittest.main()

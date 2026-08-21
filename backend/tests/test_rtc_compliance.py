from datetime import date
from decimal import Decimal
from types import SimpleNamespace
import unittest

from app.services.rtc_compliance import (
    RTC_HOMOLOGATION_CRT3_MANDATORY_FROM,
    RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM,
    RtcComplianceError,
    fiscal_product_issues,
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

    def test_pending_list_does_not_require_rtc_before_its_effective_date(self) -> None:
        current = product("Produto MEI")

        issues = fiscal_product_issues(
            setting(crt="4", tax_regime="mei"),
            current,
            model="65",
            issue_date=date(2026, 8, 8),
        )

        self.assertNotIn("CST IBS/CBS deve ter 3 dígitos", issues)
        self.assertNotIn("cClassTrib IBS/CBS deve ter 6 dígitos", issues)

    def test_pending_list_reports_ncm_even_when_rtc_is_not_mandatory(self) -> None:
        issues = fiscal_product_issues(
            setting(crt="4", tax_regime="mei"),
            product("Produto sem NCM", ncm=None),
            model="65",
            issue_date=date(2026, 8, 8),
        )

        self.assertEqual(issues, ["NCM deve ter 8 dígitos"])

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
        current_product = product("Produto", cfop=None)

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

    def test_explicit_product_values_win_over_automatic_rule(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")
        issuer.output_rules = [
            SimpleNamespace(
                id=10,
                active=True,
                priority=100,
                operation_type="sale",
                document_model="65",
                crt=None,
                tax_regime=None,
                uf_origin=None,
                uf_destination=None,
                product_id=None,
                ncm=None,
                ncm_prefix=None,
                cest=None,
                effective_from=None,
                effective_to=None,
                cfop="5405",
                origin="1",
                cst="60",
                csosn=None,
                pis_cst="04",
                cofins_cst="04",
                icms_rate=Decimal("18"),
                pis_rate=None,
                cofins_rate=None,
                ibs_cbs_cst="200",
                ibs_cbs_classification="200001",
                cbs_rate=None,
                ibs_state_rate=None,
                ibs_city_rate=None,
                selective_tax_cst=None,
                selective_tax_classification=None,
                selective_tax_rate=None,
            )
        ]
        current = product(
            "Produto configurado",
            cfop="5102",
            rtc_cst="000",
            rtc_classification="000001",
        )
        current.origin = "0"
        current.cst = "00"
        current.icms_rate = Decimal("12")

        profile = resolve_output_tax_profile(issuer, current, model="65")

        self.assertEqual(profile.cfop, "5102")
        self.assertEqual(profile.origin, "0")
        self.assertEqual(profile.cst, "00")
        self.assertEqual(profile.icms_rate, Decimal("12"))
        self.assertEqual(profile.ibs_cbs_cst, "000")
        self.assertEqual(profile.ibs_cbs_classification, "000001")

    def test_rule_only_fills_product_gaps(self) -> None:
        issuer = setting(crt="3", tax_regime="regime_normal")
        issuer.output_rules = [
            SimpleNamespace(
                id=11,
                active=True,
                priority=100,
                operation_type="sale",
                document_model="65",
                crt=None,
                tax_regime=None,
                uf_origin=None,
                uf_destination=None,
                product_id=None,
                ncm=None,
                ncm_prefix=None,
                cest=None,
                effective_from=None,
                effective_to=None,
                cfop="5405",
                origin="1",
                cst="60",
                csosn=None,
                pis_cst="04",
                cofins_cst="04",
                icms_rate=Decimal("18"),
                pis_rate=None,
                cofins_rate=None,
                ibs_cbs_cst="200",
                ibs_cbs_classification="200001",
                cbs_rate=None,
                ibs_state_rate=None,
                ibs_city_rate=None,
                selective_tax_cst=None,
                selective_tax_classification=None,
                selective_tax_rate=None,
            )
        ]
        current = product("Produto incompleto", cfop=None)
        current.origin = None
        current.cst = None
        current.icms_rate = None

        profile = resolve_output_tax_profile(issuer, current, model="65")

        self.assertEqual(profile.cfop, "5405")
        self.assertEqual(profile.origin, "1")
        self.assertEqual(profile.cst, "60")
        self.assertEqual(profile.icms_rate, Decimal("18"))
        self.assertEqual(profile.ibs_cbs_cst, "200")


if __name__ == "__main__":
    unittest.main()

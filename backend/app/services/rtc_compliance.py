from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

from app.services.fiscal_output_rules import effective_crt, resolve_output_tax_profile


RTC_HOMOLOGATION_CRT3_MANDATORY_FROM = date(2026, 7, 1)
RTC_PRODUCTION_CRT3_MANDATORY_FROM: date | None = None
RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM = date(2027, 1, 4)


@dataclass(frozen=True)
class RtcRates:
    cbs: Decimal
    ibs_uf: Decimal
    ibs_mun: Decimal


RTC_2026_RATES = RtcRates(
    cbs=Decimal("0.9000"),
    ibs_uf=Decimal("0.1000"),
    ibs_mun=Decimal("0.0000"),
)


class RtcComplianceError(ValueError):
    pass


def is_rtc_mandatory(setting: Any, issue_date: date | None = None) -> bool:
    """Return whether IBS/CBS is mandatory for this issuer on this date."""

    current_date = issue_date or date.today()
    crt = effective_crt(setting)
    environment = str(getattr(setting, "environment", "") or "").lower()
    if environment == "homologacao":
        return crt == "3" and current_date >= RTC_HOMOLOGATION_CRT3_MANDATORY_FROM
    if crt == "3":
        return (
            RTC_PRODUCTION_CRT3_MANDATORY_FROM is not None
            and current_date >= RTC_PRODUCTION_CRT3_MANDATORY_FROM
        )
    if crt in {"1", "2", "4"}:
        return current_date >= RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM
    return False


def rtc_rates_for(issue_date: date) -> RtcRates:
    if issue_date.year == 2026:
        return RTC_2026_RATES
    raise RtcComplianceError(
        f"Alíquotas IBS/CBS não catalogadas para {issue_date.year}. "
        "Atualize o catálogo fiscal antes de emitir."
    )


def _digits(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))


def rtc_product_issues(setting: Any, product: Any, *, model: str) -> list[str]:
    """Return every missing RTC field for one product/output operation."""

    profile = resolve_output_tax_profile(setting, product, model=model)
    issues: list[str] = []
    if len(_digits(getattr(product, "ncm", None))) != 8:
        issues.append("NCM deve ter 8 dígitos")
    if len(_digits(profile.cfop)) != 4:
        issues.append("CFOP de saída deve ter 4 dígitos")
    if len(_digits(profile.ibs_cbs_cst)) != 3:
        issues.append("CST IBS/CBS deve ter 3 dígitos")
    if len(_digits(profile.ibs_cbs_classification)) != 6:
        issues.append("cClassTrib IBS/CBS deve ter 6 dígitos")
    return issues


def fiscal_product_issues(
    setting: Any,
    product: Any,
    *,
    model: str,
    issue_date: date | None = None,
) -> list[str]:
    """Retorna somente pendências exigíveis para a emissão na data informada."""

    profile = resolve_output_tax_profile(setting, product, model=model)
    issues: list[str] = []
    if len(_digits(getattr(product, "ncm", None))) != 8:
        issues.append("NCM deve ter 8 dígitos")
    if len(_digits(profile.cfop)) != 4:
        issues.append("CFOP de saída deve ter 4 dígitos")

    crt = effective_crt(setting)
    if crt == "3":
        if len(_digits(profile.cst)) != 2:
            issues.append("CST ICMS deve ter 2 dígitos")
    elif len(_digits(profile.csosn)) != 3:
        issues.append("CSOSN deve ter 3 dígitos")

    if is_rtc_mandatory(setting, issue_date):
        for issue in rtc_product_issues(setting, product, model=model):
            if issue not in issues:
                issues.append(issue)
    return issues


def validate_rtc_document(
    setting: Any,
    sale: Any,
    *,
    model: str,
    issue_date: date | None = None,
) -> None:
    """Valida dados fiscais exigíveis antes de reservar número e transmitir."""

    current_date = issue_date or date.today()
    if is_rtc_mandatory(setting, current_date):
        rtc_rates_for(current_date)
    issues: list[str] = []
    for index, item in enumerate(getattr(sale, "items", None) or [], start=1):
        product = getattr(item, "product", None)
        label = getattr(product, "name", None) or f"item {index}"
        if product is None:
            issues.append(f"{label}: produto não encontrado")
            continue
        for issue in fiscal_product_issues(
            setting,
            product,
            model=model,
            issue_date=current_date,
        ):
            issues.append(f"{label}: {issue}")

    if issues:
        unique_issues = list(dict.fromkeys(issues))
        raise RtcComplianceError(
            "Emissão aguardando configuração fiscal. "
            + "; ".join(unique_issues)
        )

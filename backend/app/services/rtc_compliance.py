from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

from app.services.fiscal_output_rules import effective_crt
from app.services.fiscal_resolver import fiscal_blocking_messages, resolve_fiscal_product


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

    resolution = resolve_fiscal_product(
        setting,
        product,
        model=model,
        rtc_mandatory=True,
    )
    return resolution.missing_fields


def fiscal_product_issues(
    setting: Any,
    product: Any,
    *,
    model: str,
    issue_date: date | None = None,
) -> list[str]:
    """Retorna somente pendências exigíveis para a emissão na data informada."""

    resolution = resolve_fiscal_product(
        setting,
        product,
        model=model,
        issue_date=issue_date,
        rtc_mandatory=is_rtc_mandatory(setting, issue_date),
    )
    return resolution.missing_fields


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
    issues = fiscal_blocking_messages(
        setting,
        list(getattr(sale, "items", None) or []),
        model=model,
        issue_date=current_date,
        rtc_mandatory=is_rtc_mandatory(setting, current_date),
    )

    if issues:
        raise RtcComplianceError(
            "Emissão aguardando configuração fiscal. "
            + "; ".join(issues)
        )

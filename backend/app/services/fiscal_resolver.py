from __future__ import annotations

import re
from dataclasses import dataclass, replace
from datetime import date
from typing import Any, Literal

from app.services.fiscal_output_rules import (
    OutputTaxProfile,
    apply_draft_tax_overrides,
    effective_crt,
    resolve_output_rule,
    resolve_output_tax_profile,
)


FiscalIssueSeverity = Literal["error", "warning", "info"]
FiscalResolutionStatus = Literal["confirmed", "suggested", "incomplete", "review"]


@dataclass(frozen=True)
class FiscalResolutionIssue:
    field: str
    message: str
    severity: FiscalIssueSeverity = "error"
    blocks_nfe: bool = True
    blocks_nfce: bool = True
    owner: str = "contador"


@dataclass(frozen=True)
class FiscalResolution:
    product_id: int | None
    product_name: str
    model: str
    operation_type: str
    status: FiscalResolutionStatus
    profile: OutputTaxProfile
    ncm: str | None
    cest: str | None
    origin: str | None
    cbenef: str | None
    rule_id: int | None
    rule_name: str | None
    issues: list[FiscalResolutionIssue]

    @property
    def blocking_issues(self) -> list[FiscalResolutionIssue]:
        return [issue for issue in self.issues if issue.severity == "error"]

    @property
    def missing_fields(self) -> list[str]:
        return [issue.message for issue in self.blocking_issues]


def digits(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))


def clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = " ".join(str(value).split())
    return text or None


def first_text(*values: Any) -> str | None:
    for value in values:
        text = clean_text(value)
        if text:
            return text
    return None


def item_or_product_value(item: Any, product: Any, field: str) -> Any:
    item_value = getattr(item, field, None) if item is not None else None
    if clean_text(item_value):
        return item_value
    if product is None:
        return None
    if field == "cfop":
        return getattr(product, "cfop_sale", None)
    return getattr(product, field, None)


def suggestion_value(suggestions: list[Any] | None, field: str) -> Any:
    if not suggestions:
        return None
    for suggestion in suggestions:
        value = getattr(suggestion, field, None)
        if clean_text(value):
            return value
    return None


def merge_profile_with_suggestions(
    profile: OutputTaxProfile,
    suggestions: list[Any] | None,
) -> OutputTaxProfile:
    if not suggestions:
        return profile
    values = {}
    for name in (
        "cfop",
        "origin",
        "cst",
        "csosn",
        "pis_cst",
        "cofins_cst",
        "ibs_cbs_cst",
        "ibs_cbs_classification",
        "cbs_rate",
        "ibs_state_rate",
        "ibs_city_rate",
        "selective_tax_cst",
        "selective_tax_classification",
        "selective_tax_rate",
    ):
        current = getattr(profile, name, None)
        if clean_text(current):
            continue
        suggested = suggestion_value(suggestions, name)
        if clean_text(suggested):
            values[name] = suggested
    if not values:
        return profile
    return replace(profile, **values, source="learned_fiscal_suggestion")


def fiscal_snapshot_from_resolution(resolution: FiscalResolution) -> dict[str, str | None]:
    profile = resolution.profile
    return {
        "ncm": resolution.ncm,
        "cest": resolution.cest,
        "cfop": clean_text(profile.cfop),
        "origin": resolution.origin,
        "cst": clean_text(profile.cst),
        "csosn": clean_text(profile.csosn),
        "pis_cst": clean_text(profile.pis_cst),
        "cofins_cst": clean_text(profile.cofins_cst),
        "cbenef": resolution.cbenef,
    }


def resolve_fiscal_product(
    setting: Any,
    product: Any,
    *,
    item: Any = None,
    model: str,
    operation_type: str = "sale",
    uf_destination: str | None = None,
    issue_date: date | None = None,
    rtc_mandatory: bool = False,
    suggestions: list[Any] | None = None,
) -> FiscalResolution:
    """Resolve dados fiscais de saida e devolve pendencias humanas.

    O produto continua sendo a base da classificacao (NCM/CEST/origem), mas
    o item da pre-nota pode carregar um snapshot/correcao manual. Isso evita
    que uma nota preparada mude quando o produto for editado depois e permite
    que a correcao por item seja respeitada na emissao.
    """

    profile = resolve_output_tax_profile(
        setting,
        product,
        model=model,
        operation_type=operation_type,
        uf_destination=uf_destination,
    )
    if item is not None:
        profile = apply_draft_tax_overrides(profile, item)
    profile = merge_profile_with_suggestions(profile, suggestions)

    matched_rule = resolve_output_rule(
        setting,
        product,
        model=model,
        operation_type=operation_type,
        uf_destination=uf_destination,
    )
    product_id = getattr(product, "id", None)
    product_name = first_text(
        getattr(item, "description", None) if item is not None else None,
        getattr(item, "fiscal_description", None) if item is not None else None,
        getattr(product, "name", None) if product is not None else None,
    ) or "Item fiscal"

    ncm = digits(item_or_product_value(item, product, "ncm")) or digits(suggestion_value(suggestions, "ncm")) or None
    cest = digits(item_or_product_value(item, product, "cest")) or digits(suggestion_value(suggestions, "cest")) or None
    cbenef = clean_text(item_or_product_value(item, product, "cbenef"))
    cfop = digits(profile.cfop) or None
    raw_origin = digits(item_or_product_value(item, product, "origin")) or None
    rule_origin = (
        digits(getattr(matched_rule, "origin", None))
        if matched_rule is not None
        else None
    ) or None
    origin = raw_origin or rule_origin or digits(suggestion_value(suggestions, "origin")) or None
    crt = effective_crt(setting)
    issues: list[FiscalResolutionIssue] = []

    if product is None:
        issues.append(
            FiscalResolutionIssue(
                field="product",
                message="produto fiscal não vinculado ao item",
                owner="cliente",
            )
        )
    if len(ncm or "") != 8:
        issues.append(
            FiscalResolutionIssue(
                field="ncm",
                message="NCM deve ter 8 dígitos",
            )
        )
    if len(cfop or "") != 4:
        issues.append(
            FiscalResolutionIssue(
                field="cfop",
                message="CFOP de saída deve ter 4 dígitos",
            )
        )
    if origin is None or len(origin) != 1:
        issues.append(
            FiscalResolutionIssue(
                field="origin",
                message="origem da mercadoria deve ser informada",
            )
        )

    if crt == "3":
        if len(digits(profile.cst)) != 2:
            issues.append(
                FiscalResolutionIssue(
                    field="cst",
                    message="CST ICMS deve ter 2 dígitos",
                )
            )
    elif len(digits(profile.csosn)) != 3:
        issues.append(
            FiscalResolutionIssue(
                field="csosn",
                message="CSOSN deve ter 3 dígitos",
            )
        )

    if rtc_mandatory:
        if len(digits(profile.ibs_cbs_cst)) != 3:
            issues.append(
                FiscalResolutionIssue(
                    field="ibs_cbs_cst",
                    message="CST IBS/CBS deve ter 3 dígitos",
                )
            )
        if len(digits(profile.ibs_cbs_classification)) != 6:
            issues.append(
                FiscalResolutionIssue(
                    field="ibs_cbs_classification",
                    message="cClassTrib IBS/CBS deve ter 6 dígitos",
                )
            )

    if not issues and product is not None:
        status: FiscalResolutionStatus = (
            "suggested"
            if profile.source
            in {
                "fiscal_output_rule",
                "product_tax_rule",
                "learned_fiscal_suggestion",
            }
            or bool(suggestions)
            else "confirmed"
        )
    elif any(issue.severity == "error" for issue in issues):
        status = "incomplete"
    else:
        status = "review"

    return FiscalResolution(
        product_id=product_id,
        product_name=product_name,
        model=model,
        operation_type=operation_type,
        status=status,
        profile=profile,
        ncm=ncm,
        cest=cest,
        origin=origin,
        cbenef=cbenef,
        rule_id=getattr(matched_rule, "id", None),
        rule_name=getattr(matched_rule, "name", None),
        issues=issues,
    )


def fiscal_blocking_messages(
    setting: Any,
    items: list[Any],
    *,
    model: str,
    issue_date: date | None = None,
    rtc_mandatory: bool = False,
) -> list[str]:
    messages: list[str] = []
    for index, item in enumerate(items, start=1):
        product = getattr(item, "product", None)
        resolution = resolve_fiscal_product(
            setting,
            product,
            item=item,
            model=model,
            issue_date=issue_date,
            rtc_mandatory=rtc_mandatory,
        )
        label = resolution.product_name or f"item {index}"
        for issue in resolution.blocking_issues:
            messages.append(f"{label}: {issue.message}")
    return list(dict.fromkeys(messages))

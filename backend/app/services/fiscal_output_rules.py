from __future__ import annotations

import re
from dataclasses import dataclass, replace
from datetime import date
from decimal import Decimal
from typing import Any

from app.models.fiscal import CompanyFiscalSetting


def digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


def normalized_tax_regime(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", "_", (value or "").strip().lower()).strip("_")


def effective_crt(setting: CompanyFiscalSetting) -> str:
    """Retorna o CRT efetivo para emissao, protegido contra cadastro antigo."""
    tax_regime = normalized_tax_regime(setting.tax_regime)
    crt = digits(setting.crt)
    if tax_regime in {"mei", "microempreendedor_individual"}:
        return "4"
    if crt in {"1", "2", "3", "4"}:
        return crt
    if tax_regime in {"simples", "simples_nacional"}:
        return "1"
    if tax_regime in {"regime_normal", "normal", "lucro_presumido", "lucro_real"}:
        return "3"
    return crt


@dataclass(frozen=True)
class OutputTaxProfile:
    cfop: str | None
    origin: str | None
    cst: str | None
    csosn: str | None
    pis_cst: str | None = "07"
    cofins_cst: str | None = "07"
    icms_rate: Decimal | int | float | None = None
    pis_rate: Decimal | int | float | None = None
    cofins_rate: Decimal | int | float | None = None
    ibs_cbs_cst: str | None = None
    ibs_cbs_classification: str | None = None
    cbs_rate: Decimal | int | float | None = None
    ibs_state_rate: Decimal | int | float | None = None
    ibs_city_rate: Decimal | int | float | None = None
    selective_tax_cst: str | None = None
    selective_tax_classification: str | None = None
    selective_tax_rate: Decimal | int | float | None = None
    source: str = "automatic"


def _clean(value: Any) -> Any:
    if isinstance(value, str):
        return value.strip() or None
    return value


def _product_value(product: Any, name: str) -> Any:
    if product is None:
        return None
    if name == "cfop":
        return _clean(getattr(product, "cfop_sale", None))
    return _clean(getattr(product, name, None))


def _first_configured(product: Any, rule: Any, name: str, default: Any = None) -> Any:
    """Preserva o cadastro explícito e usa a regra apenas para completar lacunas."""

    product_value = _product_value(product, name)
    if product_value is not None:
        return product_value
    rule_value = _clean(getattr(rule, name, None)) if rule is not None else None
    return rule_value if rule_value is not None else default


class _OutputTaxProductProxy:
    def __init__(self, product: Any, profile: OutputTaxProfile):
        self._product = product
        self._profile = profile

    def __getattr__(self, name: str) -> Any:
        if hasattr(self._profile, name):
            value = getattr(self._profile, name)
            if value is not None:
                return value
        if name == "new_tax_system" and (
            self._profile.ibs_cbs_cst or self._profile.ibs_cbs_classification
        ):
            return True
        return getattr(self._product, name)


def product_with_output_tax_profile(product: Any, profile: OutputTaxProfile) -> Any:
    """Retorna o produto com sobrescritas fiscais da regra escolhida.

    Usado somente na montagem do XML. Nao grava nada no cadastro do produto.
    """
    if product is None:
        return None
    return _OutputTaxProductProxy(product, profile)


def _product_rule_for_model(product: Any, *, model: str) -> Any | None:
    rules = getattr(product, "tax_rules", None)
    if not rules:
        return None
    candidates = []
    for rule in rules:
        if getattr(rule, "operation_type", "sale") not in {"sale", "venda"}:
            continue
        notes = (getattr(rule, "notes", None) or "").lower()
        if model == "65" and ("modelo=55" in notes or "nfe" in notes):
            continue
        if model == "55" and ("modelo=65" in notes or "nfce" in notes):
            continue
        candidates.append(rule)
    if not candidates:
        return None
    return sorted(
        candidates,
        key=lambda rule: (
            1 if getattr(rule, "uf", None) else 0,
            getattr(rule, "effective_from", None) is not None,
            getattr(rule, "id", 0) or 0,
        ),
        reverse=True,
    )[0]


def _same_or_empty(rule_value: Any, current_value: Any) -> bool:
    rule_text = str(rule_value or "").strip().lower()
    if not rule_text:
        return True
    return rule_text == str(current_value or "").strip().lower()


def _digits_same_or_empty(rule_value: Any, current_value: Any) -> bool:
    rule_digits = digits(str(rule_value or ""))
    if not rule_digits:
        return True
    return rule_digits == digits(str(current_value or ""))


def _rule_matches(
    rule: Any,
    setting: CompanyFiscalSetting,
    product: Any,
    *,
    model: str,
    operation_type: str,
    uf_destination: str | None = None,
) -> bool:
    if not getattr(rule, "active", True):
        return False
    today = date.today()
    if getattr(rule, "effective_from", None) and getattr(rule, "effective_from") > today:
        return False
    if getattr(rule, "effective_to", None) and getattr(rule, "effective_to") < today:
        return False
    if not _same_or_empty(getattr(rule, "operation_type", None), operation_type):
        return False
    if not _same_or_empty(getattr(rule, "document_model", None), model):
        return False
    if not _same_or_empty(getattr(rule, "crt", None), effective_crt(setting)):
        return False
    if not _same_or_empty(getattr(rule, "tax_regime", None), normalized_tax_regime(setting.tax_regime)):
        return False
    if not _same_or_empty(getattr(rule, "uf_origin", None), getattr(setting, "uf", None)):
        return False
    if not _same_or_empty(getattr(rule, "uf_destination", None), uf_destination):
        return False
    product_id = getattr(rule, "product_id", None)
    if product_id is not None and product is not None and product_id != getattr(product, "id", None):
        return False
    if product_id is not None and product is None:
        return False
    if product is not None:
        product_ncm = digits(getattr(product, "ncm", None))
        rule_ncm = digits(getattr(rule, "ncm", None))
        if rule_ncm and rule_ncm != product_ncm:
            return False
        rule_prefix = digits(getattr(rule, "ncm_prefix", None))
        if rule_prefix and not product_ncm.startswith(rule_prefix):
            return False
        if not _digits_same_or_empty(getattr(rule, "cest", None), getattr(product, "cest", None)):
            return False
    return True


def _specificity(rule: Any, product: Any) -> tuple[int, int, int]:
    score = 0
    if getattr(rule, "product_id", None):
        score += 100
    if getattr(rule, "ncm", None):
        score += 60
    if getattr(rule, "cest", None):
        score += 40
    if getattr(rule, "ncm_prefix", None):
        score += 20 + min(len(digits(getattr(rule, "ncm_prefix", None))), 8)
    if getattr(rule, "document_model", None):
        score += 10
    if getattr(rule, "crt", None) or getattr(rule, "tax_regime", None):
        score += 8
    if getattr(rule, "uf_origin", None) or getattr(rule, "uf_destination", None):
        score += 5
    return (
        score,
        int(getattr(rule, "priority", 100) or 100),
        int(getattr(rule, "id", 0) or 0),
    )


def _output_rule_for_model(
    setting: CompanyFiscalSetting,
    product: Any,
    *,
    model: str,
    operation_type: str,
    uf_destination: str | None = None,
) -> Any | None:
    rules = getattr(setting, "output_rules", None) or []
    candidates = [
        rule
        for rule in rules
        if _rule_matches(
            rule,
            setting,
            product,
            model=model,
            operation_type=operation_type,
            uf_destination=uf_destination,
        )
    ]
    if not candidates:
        return None
    return sorted(candidates, key=lambda rule: _specificity(rule, product), reverse=True)[0]


def resolve_output_rule(
    setting: CompanyFiscalSetting,
    product: Any,
    *,
    model: str,
    operation_type: str = "sale",
    uf_destination: str | None = None,
) -> Any | None:
    """Retorna a regra de saida que seria aplicada ao produto/documento."""

    rule = _output_rule_for_model(
        setting,
        product,
        model=model,
        operation_type=operation_type,
        uf_destination=uf_destination,
    )
    if rule is None and product is not None:
        rule = _product_rule_for_model(product, model=model)
    return rule


def effective_csosn(setting: CompanyFiscalSetting, product: Any, *, model: str) -> str | None:
    csosn = (digits(getattr(product, "csosn", None)) or None) if product is not None else None
    crt = effective_crt(setting)
    if crt == "4":
        allowed = {"102", "300"} if model == "65" else {"102", "300", "400", "900"}
        return csosn if csosn in allowed else "102"
    if crt in {"1", "2"}:
        return csosn or "102"
    return csosn


def resolve_output_tax_profile(
    setting: CompanyFiscalSetting,
    product: Any,
    *,
    model: str,
    operation_type: str = "sale",
    uf_destination: str | None = None,
) -> OutputTaxProfile:
    """Resolve a tributacao de saida sem sobrescrever o cadastro do produto.

    A ordem de precedência é cadastro explícito, regra fiscal aplicável e,
    por último, padrão seguro do emitente. A regra apenas completa lacunas.
    """
    rule = resolve_output_rule(
        setting,
        product,
        model=model,
        operation_type=operation_type,
        uf_destination=uf_destination,
    )
    if rule is None and product is not None:
        rule = _product_rule_for_model(product, model=model)
    crt = effective_crt(setting)
    origin_uf = str(getattr(setting, "uf", "") or "").upper()
    destination_uf = str(uf_destination or origin_uf).upper()
    default_cfop = None
    if operation_type in {"sale", "venda"}:
        default_cfop = "6102" if destination_uf and destination_uf != origin_uf else "5102"
    default_origin = "0"

    if rule is not None:
        resolved_csosn = _first_configured(product, rule, "csosn")
        rule_product = type(
            "_RuleProduct",
            (),
            {"csosn": digits(resolved_csosn) or None},
        )()
        return OutputTaxProfile(
            cfop=_first_configured(product, rule, "cfop", default_cfop),
            origin=_first_configured(product, rule, "origin", default_origin),
            cst=_first_configured(product, rule, "cst"),
            csosn=effective_csosn(setting, rule_product, model=model),
            pis_cst=_first_configured(product, rule, "pis_cst", "07"),
            cofins_cst=_first_configured(product, rule, "cofins_cst", "07"),
            icms_rate=_first_configured(product, rule, "icms_rate"),
            pis_rate=_first_configured(product, rule, "pis_rate"),
            cofins_rate=_first_configured(product, rule, "cofins_rate"),
            ibs_cbs_cst=_first_configured(product, rule, "ibs_cbs_cst"),
            ibs_cbs_classification=_first_configured(
                product, rule, "ibs_cbs_classification"
            ),
            cbs_rate=_first_configured(product, rule, "cbs_rate"),
            ibs_state_rate=_first_configured(product, rule, "ibs_state_rate"),
            ibs_city_rate=_first_configured(product, rule, "ibs_city_rate"),
            selective_tax_cst=_first_configured(product, rule, "selective_tax_cst"),
            selective_tax_classification=_first_configured(
                product, rule, "selective_tax_classification"
            ),
            selective_tax_rate=_first_configured(product, rule, "selective_tax_rate"),
            source="fiscal_output_rule" if rule.__class__.__name__ == "FiscalOutputRule" else "product_tax_rule",
        )

    product_csosn = effective_csosn(setting, product, model=model)
    default_cst = "00" if crt == "3" else None
    return OutputTaxProfile(
        cfop=_product_value(product, "cfop") or default_cfop,
        origin=_clean(getattr(product, "origin", None)) or default_origin,
        cst=_clean(getattr(product, "cst", None)) or default_cst,
        csosn=product_csosn,
        pis_cst="07",
        cofins_cst="07",
        icms_rate=getattr(product, "icms_rate", None),
        pis_rate=getattr(product, "pis_rate", None),
        cofins_rate=getattr(product, "cofins_rate", None),
        ibs_cbs_cst=getattr(product, "ibs_cbs_cst", None),
        ibs_cbs_classification=getattr(product, "ibs_cbs_classification", None),
        cbs_rate=getattr(product, "cbs_rate", None),
        ibs_state_rate=getattr(product, "ibs_state_rate", None),
        ibs_city_rate=getattr(product, "ibs_city_rate", None),
        selective_tax_cst=getattr(product, "selective_tax_cst", None),
        selective_tax_classification=getattr(product, "selective_tax_classification", None),
        selective_tax_rate=getattr(product, "selective_tax_rate", None),
        source="product_or_default",
    )


def apply_draft_tax_overrides(profile: OutputTaxProfile, item: Any) -> OutputTaxProfile:
    """Aplica somente valores explicitamente gravados no item do rascunho."""
    values = {
        name: _clean(getattr(item, name, None))
        for name in (
            "cfop",
            "origin",
            "cst",
            "csosn",
            "pis_cst",
            "cofins_cst",
            "ibs_cbs_cst",
            "ibs_cbs_classification",
            "selective_tax_cst",
            "selective_tax_classification",
        )
        if _clean(getattr(item, name, None)) is not None
    }
    if not values:
        return profile
    return replace(profile, **values, source="manual_item_override")

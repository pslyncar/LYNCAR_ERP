"""Pre-flight fiscal rules shared by NF-e and NFC-e output documents.

The SEFAZ validates CFOP direction and destination only after the fiscal
number/key has already been reserved. This module mirrors the deterministic
part of those validations before transmission, so an unsafe document never
consumes numbering.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any, Literal


FiscalOperationType = Literal["sale", "return", "transfer", "bonus", "remittance"]
FiscalDestination = Literal["internal", "interstate", "external", "unknown"]


@dataclass(frozen=True)
class FiscalOperationContext:
    """Facts used to decide and validate an outbound fiscal operation."""

    operation_type: FiscalOperationType
    document_model: str
    issuer_uf: str | None
    recipient_uf: str | None
    recipient_country_code: str | None = None
    direction: Literal["outbound", "inbound"] = "outbound"

    @property
    def destination(self) -> FiscalDestination:
        country = _digits(self.recipient_country_code)
        if country and country != "1058":
            return "external"
        issuer = _uf(self.issuer_uf)
        recipient = _uf(self.recipient_uf)
        if not issuer or not recipient:
            return "unknown"
        return "internal" if issuer == recipient else "interstate"


def operation_type_from_nature(value: str | None) -> FiscalOperationType:
    """Map the existing human-facing nature label to the fiscal rule family."""

    nature = _normalize(value)
    if "devolu" in nature:
        return "return"
    if "transfer" in nature:
        return "transfer"
    if "bonifica" in nature or "brinde" in nature:
        return "bonus"
    if "remessa" in nature or "consign" in nature:
        return "remittance"
    return "sale"


def cfop_compatibility_issues(
    cfop: str | None,
    context: FiscalOperationContext,
) -> list[str]:
    """Return human-readable blocking incompatibilities for a CFOP."""

    code = _digits(cfop)
    if len(code) != 4:
        return ["CFOP deve ter 4 digitos."]

    family = code[0]
    if context.direction == "outbound" and family in {"1", "2", "3"}:
        return [
            f"CFOP {code} e de entrada e nao pode ser usado em documento fiscal de saida."
        ]
    if context.direction == "inbound" and family in {"5", "6", "7"}:
        return [
            f"CFOP {code} e de saida e nao pode ser usado em documento fiscal de entrada."
        ]

    destination = context.destination
    if destination == "internal" and family not in {"1", "5"}:
        return [
            f"CFOP {code} nao corresponde a operacao interna ({_display_uf(context.issuer_uf)} → {_display_uf(context.recipient_uf)})."
        ]
    if destination == "interstate" and family not in {"2", "6"}:
        return [
            f"CFOP {code} nao corresponde a operacao interestadual ({_display_uf(context.issuer_uf)} → {_display_uf(context.recipient_uf)})."
        ]
    if destination == "external" and family not in {"3", "7"}:
        return [f"CFOP {code} nao corresponde a operacao com o exterior."]
    return []


def document_cfop_issues(document: Any, setting: Any, fiscal_sale: Any) -> list[str]:
    """Validate the final item snapshots that will be serialized into XML."""

    recipient = getattr(fiscal_sale, "client", None)
    context = FiscalOperationContext(
        operation_type=operation_type_from_nature(getattr(document, "operation_nature", None)),
        document_model=str(getattr(document, "model", "") or ""),
        issuer_uf=getattr(setting, "uf", None),
        recipient_uf=getattr(recipient, "state", None),
        recipient_country_code=getattr(recipient, "country_code", None),
    )
    issues: list[str] = []
    for position, item in enumerate(getattr(fiscal_sale, "items", []) or [], start=1):
        product = getattr(item, "product", None)
        item_cfop = getattr(item, "cfop", None) or getattr(product, "cfop_sale", None)
        item_issues = cfop_compatibility_issues(item_cfop, context)
        if item_issues:
            description = getattr(item, "description", None) or "produto"
            issues.extend(f"Item {position} ({description}): {message}" for message in item_issues)
    return issues


def _digits(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))


def _normalize(value: str | None) -> str:
    return " ".join(str(value or "").lower().split())


def _uf(value: str | None) -> str | None:
    text = str(value or "").strip().upper()
    return text if len(text) == 2 and text.isalpha() else None


def _display_uf(value: str | None) -> str:
    return _uf(value) or "UF nao informada"

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.services.fiscal_output_rules import digits


SUPPORTED_NFE_UFS = {"SP"}
SUPPORTED_NFCE_UFS = {"SP"}


@dataclass(frozen=True)
class FiscalDocumentPolicy:
    model: str
    document_type: str
    reason: str


def recipient_is_icms_taxpayer(client: Any | None) -> bool:
    if client is None:
        return False
    indicator = str(getattr(client, "tax_contributor_type", "") or "").strip().lower()
    if indicator in {"1", "contribuinte", "icms"}:
        return True
    if indicator in {"2", "9", "isento", "nao_contribuinte", "não_contribuinte"}:
        return False
    return bool(digits(getattr(client, "state_registration", None)))


def choose_fiscal_document_policy(setting: Any, client: Any | None, *, prefer_nfce: bool = True) -> FiscalDocumentPolicy:
    origin_uf = str(getattr(setting, "uf", "") or "").upper()
    destination_uf = str(getattr(client, "state", None) or origin_uf).upper()
    if not prefer_nfce:
        return FiscalDocumentPolicy("55", "nfe", "NF-e solicitada explicitamente.")
    if client is not None and destination_uf and destination_uf != origin_uf:
        return FiscalDocumentPolicy("55", "nfe", "Venda interestadual deve usar NF-e.")
    if recipient_is_icms_taxpayer(client):
        return FiscalDocumentPolicy("55", "nfe", "Destinatario contribuinte de ICMS deve usar NF-e.")
    if origin_uf in SUPPORTED_NFCE_UFS:
        return FiscalDocumentPolicy("65", "nfce", "Venda presencial a consumidor final pode usar NFC-e.")
    return FiscalDocumentPolicy("55", "nfe", "NFC-e ainda nao habilitada para a UF do emitente.")


def assert_supported_authorizer(setting: Any, *, model: str) -> None:
    uf = str(getattr(setting, "uf", "") or "").upper()
    if model == "55" and uf not in SUPPORTED_NFE_UFS:
        raise ValueError(
            f"Motor NF-e da UF {uf or '?'} ainda nao possui webservice configurado. "
            "Cadastre o autorizador da UF antes de transmitir."
        )
    if model == "65" and uf not in SUPPORTED_NFCE_UFS:
        raise ValueError(
            f"Motor NFC-e da UF {uf or '?'} ainda nao possui webservice configurado. "
            "Cadastre o autorizador da UF antes de transmitir."
        )

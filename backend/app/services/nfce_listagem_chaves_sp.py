from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

import requests_pkcs12
from lxml import etree

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting
from app.services.fiscal_certificate import decrypt_certificate_bytes, decrypt_secret
from app.services.nfce_sp import NfceValidationError

SOAP_NS = "http://www.w3.org/2003/05/soap-envelope"
SAE_NS = "http://www.portalfiscal.inf.br/nfe"
LISTAGEM_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFCeListagemChaves"
LISTAGEM_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFCeListagemChaves/nfceListagemChaves"
NFCE_LISTAGEM_URLS = {
    "homologacao": "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFCeListagemChaves.asmx",
    "producao": "https://nfce.fazenda.sp.gov.br/ws/NFCeListagemChaves.asmx",
}


@dataclass(frozen=True)
class NfceNumberSyncResult:
    environment: str
    series: int
    current_next_number: int
    highest_authorized_number: int | None
    suggested_next_number: int
    updated_next_number: int
    keys_count: int
    incomplete: bool
    status_code: str | None
    message: str


def _digits(value: str | None) -> str:
    return "".join(char for char in value or "" if char.isdigit())


def _load_certificate(setting: CompanyFiscalSetting) -> tuple[bytes, str]:
    if not setting.certificate_encrypted_blob or not setting.certificate_password_encrypted:
        raise NfceValidationError("Certificado A1 nao configurado.")
    return (
        decrypt_certificate_bytes(setting.certificate_encrypted_blob),
        decrypt_secret(setting.certificate_password_encrypted),
    )


def _format_request_datetime(value: datetime) -> str:
    return value.replace(second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M")


def _build_envelope(setting: CompanyFiscalSetting, start: datetime, end: datetime) -> str:
    tp_amb = "2" if setting.environment == "homologacao" else "1"
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(
        body,
        f"{{{LISTAGEM_WSDL_NS}}}nfeDadosMsg",
        nsmap={None: LISTAGEM_WSDL_NS},
    )
    request = etree.SubElement(msg, f"{{{SAE_NS}}}nfceListagemChaves", versao="1.00", nsmap={None: SAE_NS})
    etree.SubElement(request, f"{{{SAE_NS}}}tpAmb").text = tp_amb
    etree.SubElement(request, f"{{{SAE_NS}}}dataHoraInicial").text = _format_request_datetime(start)
    etree.SubElement(request, f"{{{SAE_NS}}}dataHoraFinal").text = _format_request_datetime(end)
    return etree.tostring(envelope, encoding="utf-8", xml_declaration=False, pretty_print=False).decode("utf-8")


def _parse_response(content: bytes) -> tuple[str | None, str, list[str], bool]:
    root = etree.fromstring(content)
    cstat = root.findtext(".//{*}retNfceListagemChaves/{*}cStat") or root.findtext(".//{*}cStat")
    message = root.findtext(".//{*}retNfceListagemChaves/{*}xMotivo") or root.findtext(".//{*}xMotivo") or ""
    keys = [
        "".join((node.text or "").split())
        for node in root.findall(".//{*}chNFCe")
        if len("".join((node.text or "").split())) == 44
    ]
    return cstat, message, keys, cstat == "101"


def _key_model(key: str) -> str:
    return key[20:22]


def _key_series(key: str) -> int | None:
    try:
        return int(key[22:25])
    except ValueError:
        return None


def _key_number(key: str) -> int | None:
    try:
        return int(key[25:34])
    except ValueError:
        return None


def list_nfce_keys(setting: CompanyFiscalSetting, *, days_back: int = 99) -> tuple[list[str], bool, str | None, str]:
    if setting.uf and setting.uf.upper() != "SP":
        raise NfceValidationError("NFCeListagemChaves esta habilitado somente para emitente SP.")
    if not _digits(setting.cnpj):
        raise NfceValidationError("CNPJ fiscal nao configurado.")
    if setting.environment not in NFCE_LISTAGEM_URLS:
        raise NfceValidationError("Ambiente fiscal invalido para NFC-e.")

    raw_cert, password = _load_certificate(setting)
    now = datetime.now()
    start = now - timedelta(days=max(1, min(days_back, 99)))
    envelope_xml = _build_envelope(setting, start, now)
    response = requests_pkcs12.post(
        NFCE_LISTAGEM_URLS[setting.environment],
        data=envelope_xml.encode("utf-8"),
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{LISTAGEM_ACTION}"',
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    cstat, message, keys, incomplete = _parse_response(response.content)
    if cstat not in {"100", "101", "107"}:
        raise NfceValidationError(f"SEFAZ {cstat or 'sem codigo'}: {message or 'retorno invalido'}.")
    return keys, incomplete, cstat, message


def sync_nfce_next_number_from_sefaz(
    setting: CompanyFiscalSetting,
    *,
    series: int | None = None,
) -> NfceNumberSyncResult:
    target_series = int(series or setting.nfce_series or 1)
    current_next = int(setting.nfce_next_number or 1)
    keys, incomplete, cstat, message = list_nfce_keys(setting)
    authorized_numbers = [
        number
        for key in keys
        if _key_model(key) == "65" and _key_series(key) == target_series
        for number in [_key_number(key)]
        if number is not None
    ]
    highest = max(authorized_numbers) if authorized_numbers else None
    suggested_next = (highest + 1) if highest is not None else current_next
    updated_next = max(current_next, suggested_next)
    return NfceNumberSyncResult(
        environment=setting.environment,
        series=target_series,
        current_next_number=current_next,
        highest_authorized_number=highest,
        suggested_next_number=suggested_next,
        updated_next_number=updated_next,
        keys_count=len(keys),
        incomplete=incomplete,
        status_code=cstat,
        message=message or "Consulta concluida.",
    )

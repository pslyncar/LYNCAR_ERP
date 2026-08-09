from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import requests_pkcs12
from lxml import etree
import xmlsec

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting, FiscalDocument
from app.services.nfce_sp import (
    DS_NS,
    NFE_NS,
    SOAP_NS,
    NFCE_SP_URLS,
    NfceValidationError,
    _digits,
    _load_certificate,
    _strip_signature_whitespace,
)
from app.services.nfe_sp import NFE_SP_URLS

EVENT_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4"
EVENT_ACTION = (
    "http://www.portalfiscal.inf.br/nfe/wsdl/"
    "NFeRecepcaoEvento4/nfeRecepcaoEvento"
)


@dataclass(frozen=True)
class FiscalEventResult:
    accepted: bool
    status_code: str | None
    message: str
    protocol: str | None
    response_xml: str


def _sign_event(root: etree._Element, setting: CompanyFiscalSetting) -> None:
    _, _, key_pem, cert_pem = _load_certificate(setting)
    inf = root.find(f".//{{{NFE_NS}}}infEvento")
    if inf is None:
        raise NfceValidationError("Evento fiscal sem infEvento.")
    signature = xmlsec.template.create(
        root,
        xmlsec.Transform.C14N,
        xmlsec.Transform.RSA_SHA1,
        ns=None,
    )
    root.append(signature)
    reference = xmlsec.template.add_reference(
        signature,
        xmlsec.Transform.SHA1,
        uri="#" + inf.attrib["Id"],
    )
    xmlsec.template.add_transform(reference, xmlsec.Transform.ENVELOPED)
    xmlsec.template.add_transform(reference, xmlsec.Transform.C14N)
    key_info = xmlsec.template.ensure_key_info(signature)
    xmlsec.template.add_x509_data(key_info)
    _strip_signature_whitespace(signature)
    xmlsec.tree.add_ids(root, ["Id"])
    key = xmlsec.Key.from_memory(key_pem, xmlsec.KeyFormat.PEM, None)
    key.load_cert_from_memory(cert_pem, xmlsec.KeyFormat.PEM)
    context = xmlsec.SignatureContext()
    context.key = key
    context.sign(signature)
    _strip_signature_whitespace(signature)


def build_cancellation_event(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    reason: str,
) -> str:
    if document.status != "authorized":
        raise NfceValidationError("Somente nota autorizada pode ser cancelada.")
    if not document.access_key or not document.sefaz_protocol:
        raise NfceValidationError("Nota sem chave de acesso ou protocolo de autorizacao.")
    normalized_reason = " ".join(reason.split())
    if len(normalized_reason) < 15 or len(normalized_reason) > 255:
        raise NfceValidationError(
            "A justificativa de cancelamento deve ter entre 15 e 255 caracteres."
        )
    sequence = "01"
    event_id = f"ID110111{document.access_key}{sequence}"
    tp_amb = "2" if setting.environment == "homologacao" else "1"
    now = datetime.now(timezone(timedelta(hours=-3))).isoformat(timespec="seconds")

    event = etree.Element(
        f"{{{NFE_NS}}}evento",
        versao="1.00",
        nsmap={None: NFE_NS},
    )
    inf = etree.SubElement(event, f"{{{NFE_NS}}}infEvento", Id=event_id)
    for tag, value in [
        ("cOrgao", "35"),
        ("tpAmb", tp_amb),
        ("CNPJ", _digits(setting.cnpj).zfill(14)),
        ("chNFe", document.access_key),
        ("dhEvento", now),
        ("tpEvento", "110111"),
        ("nSeqEvento", "1"),
        ("verEvento", "1.00"),
    ]:
        child = etree.SubElement(inf, f"{{{NFE_NS}}}{tag}")
        child.text = value
    detail = etree.SubElement(
        inf,
        f"{{{NFE_NS}}}detEvento",
        versao="1.00",
    )
    etree.SubElement(detail, f"{{{NFE_NS}}}descEvento").text = "Cancelamento"
    etree.SubElement(detail, f"{{{NFE_NS}}}nProt").text = document.sefaz_protocol
    etree.SubElement(detail, f"{{{NFE_NS}}}xJust").text = normalized_reason
    _sign_event(event, setting)
    return etree.tostring(event, encoding="unicode", xml_declaration=False)


def send_cancellation_event(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    reason: str,
) -> FiscalEventResult:
    event_xml = build_cancellation_event(setting, document, reason)
    raw_cert, password, _, _ = _load_certificate(setting)
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(
        body,
        f"{{{EVENT_WSDL_NS}}}nfeDadosMsg",
        nsmap={None: EVENT_WSDL_NS},
    )
    event_batch = etree.SubElement(
        msg,
        f"{{{NFE_NS}}}envEvento",
        versao="1.00",
        nsmap={None: NFE_NS},
    )
    etree.SubElement(event_batch, f"{{{NFE_NS}}}idLote").text = datetime.utcnow().strftime(
        "%Y%m%d%H%M%S%f"
    )[:15]
    event_batch.append(etree.fromstring(event_xml.encode("utf-8")))
    payload = etree.tostring(envelope, encoding="utf-8", pretty_print=False)
    urls = NFCE_SP_URLS if document.document_type == "nfce" else NFE_SP_URLS
    event_url = urls[setting.environment].get("evento")
    if not event_url:
        event_url = (
            "https://homologacao.nfe.fazenda.sp.gov.br/ws/nferecepcaoevento4.asmx"
            if setting.environment == "homologacao"
            else "https://nfe.fazenda.sp.gov.br/ws/nferecepcaoevento4.asmx"
        )
    response = requests_pkcs12.post(
        event_url,
        data=payload,
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": (
                'application/soap+xml; charset=utf-8; '
                f'action="{EVENT_ACTION}"'
            ),
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    root = etree.fromstring(response.content)
    response_xml = etree.tostring(root, encoding="unicode")
    info = root.find(f".//{{{NFE_NS}}}retEvento/{{{NFE_NS}}}infEvento")
    if info is None:
        info = root.find(f".//{{{NFE_NS}}}infEvento")
    status_code = (
        info.findtext(f"{{{NFE_NS}}}cStat")
        if info is not None
        else root.findtext(f".//{{{NFE_NS}}}cStat")
    )
    message = (
        info.findtext(f"{{{NFE_NS}}}xMotivo")
        if info is not None
        else root.findtext(f".//{{{NFE_NS}}}xMotivo")
    ) or "Retorno SEFAZ sem mensagem."
    protocol = (
        info.findtext(f"{{{NFE_NS}}}nProt") if info is not None else None
    )
    return FiscalEventResult(
        accepted=status_code in {"135", "155"},
        status_code=status_code,
        message=message,
        protocol=protocol,
        response_xml=response_xml,
    )

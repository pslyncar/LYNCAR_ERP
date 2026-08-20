from __future__ import annotations

from dataclasses import dataclass

import requests_pkcs12
from lxml import etree

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting
from app.services.nfce_sp import NFE_NS, SOAP_NS, _load_certificate

CONSULTA_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeConsultaProtocolo4"
CONSULTA_ACTION = (
    "http://www.portalfiscal.inf.br/nfe/wsdl/"
    "NFeConsultaProtocolo4/nfeConsultaNF"
)
CONSULTA_URLS = {
    "homologacao": "https://homologacao.nfe.fazenda.sp.gov.br/ws/nfeconsultaprotocolo4.asmx",
    "producao": "https://nfe.fazenda.sp.gov.br/ws/nfeconsultaprotocolo4.asmx",
}


@dataclass(frozen=True)
class NfeProtocolResult:
    authorized: bool
    status_code: str | None
    message: str
    protocol: str | None
    response_xml: str


def build_nfe_protocol_envelope(setting: CompanyFiscalSetting, access_key: str) -> str:
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(
        body,
        f"{{{CONSULTA_WSDL_NS}}}nfeDadosMsg",
        nsmap={None: CONSULTA_WSDL_NS},
    )
    request = etree.SubElement(
        msg,
        f"{{{NFE_NS}}}consSitNFe",
        versao="4.00",
        nsmap={None: NFE_NS},
    )
    etree.SubElement(request, f"{{{NFE_NS}}}tpAmb").text = (
        "2" if setting.environment == "homologacao" else "1"
    )
    etree.SubElement(request, f"{{{NFE_NS}}}xServ").text = "CONSULTAR"
    etree.SubElement(request, f"{{{NFE_NS}}}chNFe").text = access_key
    return etree.tostring(
        envelope,
        encoding="utf-8",
        xml_declaration=False,
        pretty_print=False,
    ).decode("utf-8")


def query_nfe_protocol(
    setting: CompanyFiscalSetting,
    access_key: str,
) -> NfeProtocolResult:
    raw_cert, password, _, _ = _load_certificate(setting)
    payload = build_nfe_protocol_envelope(setting, access_key)
    response = requests_pkcs12.post(
        CONSULTA_URLS[setting.environment],
        data=payload.encode("utf-8"),
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": (
                "application/soap+xml; charset=utf-8; "
                f'action="{CONSULTA_ACTION}"'
            ),
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    root = etree.fromstring(response.content)
    protocol_node = root.find(f".//{{{NFE_NS}}}protNFe/{{{NFE_NS}}}infProt")
    status_code = (
        protocol_node.findtext(f"{{{NFE_NS}}}cStat")
        if protocol_node is not None
        else root.findtext(f".//{{{NFE_NS}}}cStat")
    )
    message = (
        protocol_node.findtext(f"{{{NFE_NS}}}xMotivo")
        if protocol_node is not None
        else root.findtext(f".//{{{NFE_NS}}}xMotivo")
    ) or "Retorno da SEFAZ sem mensagem."
    protocol = (
        protocol_node.findtext(f"{{{NFE_NS}}}nProt")
        if protocol_node is not None
        else root.findtext(f".//{{{NFE_NS}}}nProt")
    )
    return NfeProtocolResult(
        authorized=status_code in {"100", "150"},
        status_code=status_code,
        message=message,
        protocol=protocol,
        response_xml=etree.tostring(root, encoding="unicode"),
    )

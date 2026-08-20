from __future__ import annotations

from copy import deepcopy

from lxml import etree

NFE_NS = "http://www.portalfiscal.inf.br/nfe"


def is_processed_nfe_xml(xml: str | None) -> bool:
    if not xml:
        return False
    try:
        return etree.QName(etree.fromstring(xml.encode("utf-8"))).localname == "nfeProc"
    except (ValueError, etree.XMLSyntaxError):
        return False


def build_processed_nfe_xml(signed_xml: str, protocol_response_xml: str) -> str:
    signed_root = etree.fromstring(signed_xml.encode("utf-8"))
    if etree.QName(signed_root).localname == "NFe":
        nfe = signed_root
    else:
        nfe = signed_root.find(f".//{{{NFE_NS}}}NFe")
    response_root = etree.fromstring(protocol_response_xml.encode("utf-8"))
    if etree.QName(response_root).localname == "nfeProc":
        return etree.tostring(
            response_root,
            encoding="unicode",
            xml_declaration=False,
        )
    protocol = response_root.find(f".//{{{NFE_NS}}}protNFe")
    if nfe is None or protocol is None:
        raise ValueError("XML assinado ou protocolo de autorização incompleto.")
    processed = etree.Element(
        f"{{{NFE_NS}}}nfeProc",
        versao="4.00",
        nsmap={None: NFE_NS},
    )
    processed.append(deepcopy(nfe))
    processed.append(deepcopy(protocol))
    return etree.tostring(
        processed,
        encoding="unicode",
        xml_declaration=False,
    )

from __future__ import annotations

import base64
import gzip
import re
import zipfile
from dataclasses import dataclass
from datetime import datetime
from io import BytesIO

import requests_pkcs12
from lxml import etree

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting
from app.services.fiscal_certificate import decrypt_certificate_bytes, decrypt_secret
from app.services.nfce_listagem_chaves_sp import list_nfce_keys
from app.services.nfce_sp import NfceValidationError

SOAP_NS = "http://www.w3.org/2003/05/soap-envelope"
NFE_NS = "http://www.portalfiscal.inf.br/nfe"
NFCE_DOWNLOAD_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFCeDownloadXML"
NFCE_DOWNLOAD_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFCeDownloadXML/nfceDownloadXML"
NFCE_DOWNLOAD_URLS = {
    "homologacao": "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFCeDownloadXML.asmx",
    "producao": "https://nfce.fazenda.sp.gov.br/ws/NFCeDownloadXML.asmx",
}
NFE_DISTRIB_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe"
NFE_DISTRIB_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse"
NFE_DISTRIB_URLS = {
    "homologacao": "https://hom1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx",
    "producao": "https://www1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx",
}
SP_UF_CODE = "35"


@dataclass(frozen=True)
class RecoveredFiscalDocument:
    document_type: str
    model: str
    access_key: str
    series: int | None = None
    number: int | None = None
    status: str = "authorized"
    environment: str = "homologacao"
    protocol: str | None = None
    status_code: str | None = None
    message: str | None = None
    issued_at: datetime | None = None
    authorized_xml: str | None = None
    source: str = "sefaz"


@dataclass(frozen=True)
class FiscalRecoveryResult:
    nfce_keys: int = 0
    nfce_existing: int = 0
    nfce_downloaded: int = 0
    nfe_docs: int = 0
    incomplete: bool = False
    max_nsu: str | None = None
    ult_nsu: str | None = None
    messages: tuple[str, ...] = ()
    documents: tuple[RecoveredFiscalDocument, ...] = ()


def _digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


def _load_certificate(setting: CompanyFiscalSetting) -> tuple[bytes, str]:
    if not setting.certificate_encrypted_blob or not setting.certificate_password_encrypted:
        raise NfceValidationError("Certificado A1 nao configurado.")
    return (
        decrypt_certificate_bytes(setting.certificate_encrypted_blob),
        decrypt_secret(setting.certificate_password_encrypted),
    )


def _tp_amb(setting: CompanyFiscalSetting) -> str:
    return "2" if setting.environment == "homologacao" else "1"


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _text(root: etree._Element, path: str) -> str | None:
    return root.findtext(path, namespaces={"n": NFE_NS})


def _document_from_xml(
    xml: str,
    *,
    fallback_key: str | None,
    document_type: str,
    source: str,
    environment: str,
) -> RecoveredFiscalDocument | None:
    try:
        root = etree.fromstring(xml.encode("utf-8") if isinstance(xml, str) else xml)
    except Exception:
        return None
    nfe = root.find(".//n:NFe", namespaces={"n": NFE_NS})
    inf = nfe.find("n:infNFe", namespaces={"n": NFE_NS}) if nfe is not None else root.find(".//n:infNFe", namespaces={"n": NFE_NS})
    if inf is None:
        return None
    access_key = (inf.attrib.get("Id") or "").replace("NFe", "", 1) or fallback_key
    if not access_key:
        return None
    model = _text(inf, "n:ide/n:mod") or access_key[20:22]
    series_text = _text(inf, "n:ide/n:serie")
    number_text = _text(inf, "n:ide/n:nNF")
    status_code = root.findtext(".//n:protNFe/n:infProt/n:cStat", namespaces={"n": NFE_NS})
    message = root.findtext(".//n:protNFe/n:infProt/n:xMotivo", namespaces={"n": NFE_NS})
    protocol = root.findtext(".//n:protNFe/n:infProt/n:nProt", namespaces={"n": NFE_NS})
    issued_at = _parse_datetime(_text(inf, "n:ide/n:dhEmi"))
    return RecoveredFiscalDocument(
        document_type=document_type,
        model=model,
        access_key=access_key,
        series=int(series_text) if series_text and series_text.isdigit() else None,
        number=int(number_text) if number_text and number_text.isdigit() else None,
        status="authorized" if status_code in {None, "100", "150"} else "imported",
        environment=environment,
        protocol=protocol,
        status_code=status_code or "100",
        message=message or "Documento recuperado da SEFAZ.",
        issued_at=issued_at,
        authorized_xml=xml,
        source=source,
    )


def _key_stub(key: str, *, environment: str, source: str) -> RecoveredFiscalDocument:
    model = key[20:22]
    document_type = "nfce" if model == "65" else "nfe"
    return RecoveredFiscalDocument(
        document_type=document_type,
        model=model,
        access_key=key,
        series=int(key[22:25]),
        number=int(key[25:34]),
        status="authorized",
        environment=environment,
        status_code="CHAVE",
        message="Chave recuperada da SEFAZ; XML completo ainda nao importado.",
        source=source,
    )


def _nfce_download_envelope(setting: CompanyFiscalSetting, key: str) -> str:
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(body, f"{{{NFCE_DOWNLOAD_WSDL_NS}}}nfeDadosMsg", nsmap={None: NFCE_DOWNLOAD_WSDL_NS})
    request = etree.SubElement(msg, f"{{{NFE_NS}}}nfceDownloadXML", versao="1.00", nsmap={None: NFE_NS})
    etree.SubElement(request, f"{{{NFE_NS}}}tpAmb").text = _tp_amb(setting)
    etree.SubElement(request, f"{{{NFE_NS}}}chNFCe").text = key
    return etree.tostring(envelope, encoding="utf-8", xml_declaration=False, pretty_print=False).decode("utf-8")


def download_nfce_xml(setting: CompanyFiscalSetting, key: str) -> RecoveredFiscalDocument:
    raw_cert, password = _load_certificate(setting)
    response = requests_pkcs12.post(
        NFCE_DOWNLOAD_URLS[setting.environment],
        data=_nfce_download_envelope(setting, key).encode("utf-8"),
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{NFCE_DOWNLOAD_ACTION}"',
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    root = etree.fromstring(response.content)
    cstat = root.findtext(".//{*}retNfceDownloadXML/{*}cStat") or root.findtext(".//{*}cStat")
    message = root.findtext(".//{*}retNfceDownloadXML/{*}xMotivo") or root.findtext(".//{*}xMotivo")
    nfe_proc = root.find(".//{*}nfeProc")
    if cstat != "200" or nfe_proc is None:
        stub = _key_stub(key, environment=setting.environment, source="nfce_listagem")
        return RecoveredFiscalDocument(**{**stub.__dict__, "status_code": cstat, "message": message or stub.message})
    xml = etree.tostring(nfe_proc, encoding="unicode", xml_declaration=False)
    return _document_from_xml(
        xml,
        fallback_key=key,
        document_type="nfce",
        source="nfce_download_xml",
        environment=setting.environment,
    ) or _key_stub(key, environment=setting.environment, source="nfce_download_xml")


def _nfe_distribution_envelope(setting: CompanyFiscalSetting, ult_nsu: str = "0") -> str:
    cnpj = _digits(setting.cnpj).zfill(14)
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    operation = etree.SubElement(body, f"{{{NFE_DISTRIB_WSDL_NS}}}nfeDistDFeInteresse", nsmap={None: NFE_DISTRIB_WSDL_NS})
    msg = etree.SubElement(operation, f"{{{NFE_DISTRIB_WSDL_NS}}}nfeDadosMsg")
    request = etree.SubElement(msg, f"{{{NFE_NS}}}distDFeInt", versao="1.01", nsmap={None: NFE_NS})
    etree.SubElement(request, f"{{{NFE_NS}}}tpAmb").text = _tp_amb(setting)
    etree.SubElement(request, f"{{{NFE_NS}}}cUFAutor").text = SP_UF_CODE
    etree.SubElement(request, f"{{{NFE_NS}}}CNPJ").text = cnpj
    dist = etree.SubElement(request, f"{{{NFE_NS}}}distNSU")
    etree.SubElement(dist, f"{{{NFE_NS}}}ultNSU").text = str(ult_nsu).zfill(15)
    return etree.tostring(envelope, encoding="utf-8", xml_declaration=False, pretty_print=False).decode("utf-8")


def _decode_doc_zip(text: str) -> str | None:
    raw = base64.b64decode(text)
    for decoder in (
        lambda data: gzip.decompress(data),
        lambda data: zipfile.ZipFile(BytesIO(data)).read(zipfile.ZipFile(BytesIO(data)).namelist()[0]),
        lambda data: data,
    ):
        try:
            return decoder(raw).decode("utf-8")
        except Exception:
            continue
    return None


def distribute_nfe_documents(setting: CompanyFiscalSetting, *, max_batches: int = 5) -> tuple[list[RecoveredFiscalDocument], str | None, str | None, list[str]]:
    raw_cert, password = _load_certificate(setting)
    ult_nsu = "0"
    max_nsu = None
    docs: list[RecoveredFiscalDocument] = []
    messages: list[str] = []
    for _ in range(max_batches):
        response = requests_pkcs12.post(
            NFE_DISTRIB_URLS[setting.environment],
            data=_nfe_distribution_envelope(setting, ult_nsu).encode("utf-8"),
            pkcs12_data=raw_cert,
            pkcs12_password=password,
            headers={
                "Content-Type": f'application/soap+xml; charset=utf-8; action="{NFE_DISTRIB_ACTION}"',
            },
            verify=get_settings().sefaz_tls_verify,
            timeout=get_settings().sefaz_timeout_seconds,
        )
        response.raise_for_status()
        root = etree.fromstring(response.content)
        cstat = root.findtext(".//{*}retDistDFeInt/{*}cStat") or root.findtext(".//{*}cStat")
        xmotivo = root.findtext(".//{*}retDistDFeInt/{*}xMotivo") or root.findtext(".//{*}xMotivo")
        ult_nsu = root.findtext(".//{*}retDistDFeInt/{*}ultNSU") or ult_nsu
        max_nsu = root.findtext(".//{*}retDistDFeInt/{*}maxNSU") or max_nsu
        messages.append(f"NFeDistribuicaoDFe {cstat}: {xmotivo}")
        if cstat not in {"137", "138"}:
            break
        for node in root.findall(".//{*}docZip"):
            schema = node.attrib.get("schema", "")
            xml = _decode_doc_zip(node.text or "")
            if not xml:
                continue
            doc = _document_from_xml(
                xml,
                fallback_key=None,
                document_type="nfe",
                source=f"nfe_distribuicao:{schema}",
                environment=setting.environment,
            )
            if doc is not None and doc.model == "55":
                docs.append(doc)
                continue
            try:
                parsed = etree.fromstring(xml.encode("utf-8"))
            except Exception:
                continue
            key = parsed.findtext(".//{*}chNFe")
            if key and len(key) == 44 and key[20:22] == "55":
                docs.append(_key_stub(key, environment=setting.environment, source=f"nfe_distribuicao:{schema}"))
        if cstat == "137" or not max_nsu or ult_nsu == max_nsu:
            break
    return docs, ult_nsu, max_nsu, messages


def recover_fiscal_documents(
    setting: CompanyFiscalSetting,
    *,
    existing_nfce_xml_keys: set[str] | None = None,
) -> FiscalRecoveryResult:
    docs: list[RecoveredFiscalDocument] = []
    messages: list[str] = []
    existing_keys = existing_nfce_xml_keys or set()
    keys, incomplete, cstat, message = list_nfce_keys(setting)
    messages.append(f"NFCeListagemChaves {cstat}: {message}")
    nfce_existing = 0
    nfce_downloaded = 0
    for key in keys:
        if key[20:22] != "65":
            continue
        if key in existing_keys:
            nfce_existing += 1
            continue
        doc = download_nfce_xml(setting, key)
        if doc.authorized_xml:
            nfce_downloaded += 1
        docs.append(doc)
        if doc.status_code == "656":
            incomplete = True
            messages.append(
                "NFCeDownloadXML 656: limite da SEFAZ atingido; a recuperação "
                "continua na próxima tentativa após o prazo informado pelo fisco."
            )
            break
    return FiscalRecoveryResult(
        nfce_keys=len(keys),
        nfce_existing=nfce_existing,
        nfce_downloaded=nfce_downloaded,
        nfe_docs=0,
        incomplete=incomplete,
        messages=tuple(messages),
        documents=tuple(docs),
    )

from __future__ import annotations

import hashlib
import base64
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from random import randint

import requests_pkcs12
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import pkcs12
from lxml import etree
import xmlsec

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting, FiscalDocument
from app.models.sale import Sale
from app.services.fiscal_certificate import decrypt_certificate_bytes, decrypt_secret
from app.services.fiscal_output_rules import (
    effective_crt as _rule_effective_crt,
    effective_csosn as _rule_effective_csosn,
    apply_draft_tax_overrides,
    product_with_output_tax_profile,
    resolve_output_tax_profile,
)
from app.services.fiscal_document_policy import assert_supported_authorizer
from app.services.fiscal_xml import build_processed_nfe_xml
from app.services.rtc_tax import RtcTaxTotals, append_ibscbs_totals, append_item_ibscbs, append_item_selective_tax
from app.services.rtc_compliance import is_rtc_mandatory

NFE_NS = "http://www.portalfiscal.inf.br/nfe"
SOAP_NS = "http://www.w3.org/2003/05/soap-envelope"
DS_NS = "http://www.w3.org/2000/09/xmldsig#"
INC_C14N = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
NFE_AUTORIZACAO_WSDL_NS = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4"
NFE_AUTORIZACAO_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote"
SP_UF_CODE = "35"
NFCE_SP_URLS = {
    "homologacao": {
        "autorizacao": "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx",
        "evento": "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRecepcaoEvento4.asmx",
        "qrcode": "https://www.homologacao.nfce.fazenda.sp.gov.br/qrcode",
        "consulta": "https://www.homologacao.nfce.fazenda.sp.gov.br/consulta",
    },
    "producao": {
        "autorizacao": "https://nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx",
        "evento": "https://nfce.fazenda.sp.gov.br/ws/NFeRecepcaoEvento4.asmx",
        "qrcode": "https://www.nfce.fazenda.sp.gov.br/qrcode",
        "consulta": "https://www.nfce.fazenda.sp.gov.br/consulta",
    },
}


class NfceValidationError(ValueError):
    pass


@dataclass(frozen=True)
class NfceResult:
    status: str
    status_code: str | None
    message: str
    protocol: str | None = None
    authorized_xml: str | None = None


def _digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


def _money(value: Decimal | int | float | None) -> str:
    amount = Decimal(value or 0).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{amount:.2f}"


def _quantity(value: Decimal | int | float | None) -> str:
    amount = Decimal(value or 0).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
    return f"{amount:.4f}"


def _valid_gtin(value: str | None) -> bool:
    digits = _digits(value)
    if len(digits) not in {8, 12, 13, 14}:
        return False
    total = 0
    body = digits[:-1]
    check_digit = int(digits[-1])
    for index, char in enumerate(reversed(body), start=1):
        total += int(char) * (3 if index % 2 == 1 else 1)
    return (10 - (total % 10)) % 10 == check_digit


def _gtin_or_sem_gtin(value: str | None) -> str:
    digits = _digits(value)
    return digits if _valid_gtin(digits) else "SEM GTIN"


def _text(parent: etree._Element, tag: str, value: object | None) -> etree._Element:
    child = etree.SubElement(parent, f"{{{NFE_NS}}}{tag}")
    child.text = "" if value is None else str(value)
    return child


def _normalized_tax_regime(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", "_", (value or "").strip().lower()).strip("_")


def _effective_crt(setting: CompanyFiscalSetting) -> str:
    return _rule_effective_crt(setting)


def _effective_csosn(setting: CompanyFiscalSetting, product, *, model: str) -> str | None:
    """CSOSN de saida, sem copiar cegamente tributacao de entrada.

    Para MEI/CRT 4, a NT 2024.001 restringe CSOSN por modelo:
    - NFC-e modelo 65: 102 ou 300.
    - NF-e modelo 55: 102, 300, 400 ou 900.
    Se o cadastro antigo veio contaminado por XML de entrada, usamos 102 como
    fallback de venda para evitar rejeicao, sem alterar o cadastro do produto.
    """
    return _rule_effective_csosn(setting, product, model=model)


def _ds_text(parent: etree._Element, tag: str, value: object | None) -> etree._Element:
    child = etree.SubElement(parent, f"{{{DS_NS}}}{tag}")
    child.text = "" if value is None else str(value)
    return child


def _strip_signature_whitespace(node: etree._Element) -> None:
    if isinstance(node.text, str) and node.text.strip() == "":
        node.text = None
    if isinstance(node.tail, str) and node.tail.strip() == "":
        node.tail = None
    for child in node:
        _strip_signature_whitespace(child)


def _check_digit(access_key_base: str) -> str:
    weight = 2
    total = 0
    for char in reversed(access_key_base):
        total += int(char) * weight
        weight = 2 if weight == 9 else weight + 1
    digit = 11 - (total % 11)
    return "0" if digit >= 10 else str(digit)


def _access_key(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    issued_at: datetime,
    random_code: str,
    emission_type: str = "1",
) -> str:
    cnpj = _digits(setting.cnpj)
    series = int(document.series or setting.nfce_series or 1)
    number = int(document.number or setting.nfce_next_number or 1)
    base = (
        SP_UF_CODE
        + issued_at.strftime("%y%m")
        + cnpj.zfill(14)
        + "65"
        + f"{series:03d}"
        + f"{number:09d}"
        + emission_type
        + random_code.zfill(8)
    )
    return base + _check_digit(base)


def _require_setting(setting: CompanyFiscalSetting) -> None:
    assert_supported_authorizer(setting, model="65")
    missing = []
    crt = _effective_crt(setting)
    for label, value in [
        ("razao social", setting.legal_name),
        ("CNPJ", setting.cnpj),
        ("inscricao estadual", setting.state_registration),
        ("CRT", crt),
        ("UF", setting.uf),
        ("codigo IBGE da cidade", setting.city_code),
        ("logradouro", setting.address_line),
        ("numero", setting.address_number),
        ("bairro", setting.neighborhood),
        ("cidade", setting.city),
        ("CEP", setting.zip_code),
        ("CSC/ID", setting.nfce_csc_id),
        ("CSC/token", setting.nfce_csc_secret_key),
    ]:
        if not value:
            missing.append(label)
    if setting.uf and setting.uf.upper() != "SP":
        missing.append("motor atual habilitado somente para UF SP")
    if crt not in {"1", "2", "3", "4"}:
        missing.append("CRT valido")
    if not setting.certificate_encrypted_blob or not setting.certificate_password_encrypted:
        missing.append("certificado A1")
    if missing:
        raise NfceValidationError("Complete a configuracao fiscal: " + ", ".join(missing) + ".")


def _require_sale(sale: Sale, setting: CompanyFiscalSetting | None = None, *, model: str = "65") -> None:
    if sale.status != "finalizada":
        raise NfceValidationError("A NFC-e so pode ser enviada para venda finalizada.")
    if not sale.items:
        raise NfceValidationError("Venda sem itens para emissao fiscal.")
    for index, item in enumerate(sale.items, start=1):
        product = item.product
        missing = []
        if product is None:
            missing.append("produto vinculado")
        else:
            tax_profile = resolve_output_tax_profile(setting, product, model=model) if setting is not None else None
            if tax_profile is not None:
                tax_profile = apply_draft_tax_overrides(tax_profile, item)
            if not _digits(getattr(item, "ncm", None) or product.ncm):
                missing.append("NCM")
            if not (tax_profile.cfop if tax_profile is not None else getattr(item, "cfop", None)):
                missing.append("CFOP de venda")
            if not (tax_profile.origin if tax_profile is not None else getattr(item, "origin", None)):
                missing.append("origem")
            if not (
                (tax_profile.csosn or tax_profile.cst)
                if tax_profile is not None
                else (getattr(item, "csosn", None) or getattr(item, "cst", None))
            ):
                missing.append("CSOSN/CST")
        if missing:
            raise NfceValidationError(f"Item {index} ({item.description}) sem " + ", ".join(missing) + ".")


def _operation_nature(document: FiscalDocument) -> str:
    return " ".join((document.operation_nature or "").split())[:60] or "VENDA DE MERCADORIA"


def _payment_indicator(document: FiscalDocument) -> str:
    return "1" if document.payment_condition == "prazo" else "0"


def _additional_info(document: FiscalDocument, default_text: str) -> str:
    notes = " ".join((document.fiscal_notes or "").split())
    if notes:
        return f"{default_text} {notes}"[:5000]
    return default_text


def _append_card_group(det_pag: etree._Element, method: str, authorization_code: str | None) -> None:
    """Informa grupo card para pagamentos eletrônicos exigidos por algumas SEFAZ.

    tpIntegra=2 representa POS/maquininha nao integrada ao sistema. Nesse caso,
    CNPJ da credenciadora, bandeira e autorizacao nao sao obrigatorios. Se a venda
    ja tiver codigo de autorizacao, ele e enviado junto.
    """
    if method not in {"03", "04", "17"}:
        return
    card = etree.SubElement(det_pag, f"{{{NFE_NS}}}card")
    _text(card, "tpIntegra", "2")
    if authorization_code:
        _text(card, "cAut", authorization_code[:20])


def _load_certificate(setting: CompanyFiscalSetting):
    raw = decrypt_certificate_bytes(setting.certificate_encrypted_blob or b"")
    password = decrypt_secret(setting.certificate_password_encrypted or "")
    private_key, certificate, extra = pkcs12.load_key_and_certificates(raw, password.encode("utf-8"))
    if private_key is None or certificate is None:
        raise NfceValidationError("Certificado A1 invalido ou sem chave privada.")
    key_pem = private_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    cert_pem = certificate.public_bytes(serialization.Encoding.PEM)
    return raw, password, key_pem, cert_pem


def build_nfce_xml(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    sale: Sale,
    *,
    emission_type: str = "1",
) -> tuple[str, str, datetime]:
    _require_setting(setting)
    _require_sale(sale, setting, model="65")
    if emission_type not in {"1", "9"}:
        raise NfceValidationError("Tipo de emissao NFC-e nao suportado pelo motor.")
    issued_at = datetime.now(timezone(timedelta(hours=-3)))
    rtc_required = is_rtc_mandatory(setting, issued_at.date())
    random_code = str(randint(1, 99999999)).zfill(8)
    if document.series is None:
        document.series = int(setting.nfce_series or 1)
    if document.number is None:
        document.number = int(setting.nfce_next_number or 1)
    access_key = _access_key(setting, document, issued_at, random_code, emission_type)
    tp_amb = "2" if setting.environment == "homologacao" else "1"

    nfe = etree.Element(f"{{{NFE_NS}}}NFe", nsmap={None: NFE_NS})
    inf = etree.SubElement(nfe, f"{{{NFE_NS}}}infNFe", versao="4.00", Id=f"NFe{access_key}")
    ide = etree.SubElement(inf, f"{{{NFE_NS}}}ide")
    for tag, value in [
        ("cUF", SP_UF_CODE),
        ("cNF", random_code),
        ("natOp", _operation_nature(document)),
        ("mod", "65"),
        ("serie", document.series),
        ("nNF", document.number),
        ("dhEmi", issued_at.isoformat(timespec="seconds")),
        ("tpNF", "1"),
        ("idDest", "1"),
        ("cMunFG", _digits(setting.city_code)),
        ("tpImp", "4"),
        ("tpEmis", emission_type),
        ("cDV", access_key[-1]),
        ("tpAmb", tp_amb),
        ("finNFe", "1"),
        ("indFinal", "1"),
        ("indPres", "1"),
        ("procEmi", "0"),
        ("verProc", "Lyncar-1.0"),
    ]:
        _text(ide, tag, value)
    if emission_type == "9":
        _text(ide, "dhCont", issued_at.isoformat(timespec="seconds"))
        _text(
            ide,
            "xJust",
            "Contingencia offline por indisponibilidade de comunicacao com a SEFAZ.",
        )

    emit = etree.SubElement(inf, f"{{{NFE_NS}}}emit")
    _text(emit, "CNPJ", _digits(setting.cnpj).zfill(14))
    _text(emit, "xNome", setting.legal_name)
    _text(emit, "xFant", setting.trade_name or setting.legal_name)
    ender = etree.SubElement(emit, f"{{{NFE_NS}}}enderEmit")
    for tag, value in [
        ("xLgr", setting.address_line),
        ("nro", setting.address_number),
        ("xBairro", setting.neighborhood),
        ("cMun", _digits(setting.city_code)),
        ("xMun", setting.city),
        ("UF", setting.uf),
        ("CEP", _digits(setting.zip_code)),
        ("cPais", "1058"),
        ("xPais", "BRASIL"),
    ]:
        _text(ender, tag, value)
    _text(emit, "IE", _digits(setting.state_registration))
    _text(emit, "CRT", _effective_crt(setting))

    recipient_document = _digits(document.consumer_cpf or sale.consumer_cpf)
    if recipient_document:
        dest = etree.SubElement(inf, f"{{{NFE_NS}}}dest")
        if len(recipient_document) == 14:
            _text(dest, "CNPJ", recipient_document)
        elif len(recipient_document) == 11:
            _text(dest, "CPF", recipient_document)
        else:
            raise NfceValidationError("CPF/CNPJ do consumidor deve ter 11 ou 14 digitos.")
        if tp_amb == "2":
            _text(dest, "xNome", "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL")
        _text(dest, "indIEDest", "9")

    total_products = Decimal("0")
    total_discount = Decimal("0")
    rtc_totals = RtcTaxTotals()
    homologation_product_name = "NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
    for index, item in enumerate(sale.items, start=1):
        product = item.product
        line_total = Decimal(item.total_price or 0)
        total_products += (Decimal(item.quantity or 0) * Decimal(item.unit_price or 0))
        total_discount += Decimal(item.discount_amount or 0)
        det = etree.SubElement(inf, f"{{{NFE_NS}}}det", nItem=str(index))
        prod = etree.SubElement(det, f"{{{NFE_NS}}}prod")
        tax_profile = resolve_output_tax_profile(setting, product, model="65")
        tax_profile = apply_draft_tax_overrides(tax_profile, item)
        for tag, value in [
            ("cProd", product.internal_code if product and product.internal_code else item.product_id or index),
            ("cEAN", _gtin_or_sem_gtin(item.barcode)),
            ("xProd", homologation_product_name if tp_amb == "2" else item.description),
            ("NCM", _digits(getattr(item, "ncm", None) or (product.ncm if product else ""))),
            ("CEST", _digits(getattr(item, "cest", None) or (getattr(product, "cest", None) if product else ""))),
            ("cBenef", getattr(item, "cbenef", None)),
            ("CFOP", tax_profile.cfop if product else ""),
            ("uCom", (item.unit or "UN").upper()[:6]),
            ("qCom", _quantity(item.quantity)),
            ("vUnCom", _money(item.unit_price)),
            ("vProd", _money(Decimal(item.quantity or 0) * Decimal(item.unit_price or 0))),
            ("cEANTrib", _gtin_or_sem_gtin(item.barcode)),
            ("uTrib", (item.unit or "UN").upper()[:6]),
            ("qTrib", _quantity(item.quantity)),
            ("vUnTrib", _money(item.unit_price)),
        ]:
            _text(prod, tag, value)
        if Decimal(item.discount_amount or 0) > 0:
            _text(prod, "vDesc", _money(item.discount_amount))
        _text(prod, "indTot", "1")

        imposto = etree.SubElement(det, f"{{{NFE_NS}}}imposto")
        icms = etree.SubElement(imposto, f"{{{NFE_NS}}}ICMS")
        csosn = tax_profile.csosn
        origin = tax_profile.origin if product else "0"
        fiscal_tax_product = product_with_output_tax_profile(product, tax_profile)
        if csosn:
            group = etree.SubElement(icms, f"{{{NFE_NS}}}ICMSSN102")
            _text(group, "orig", origin)
            _text(group, "CSOSN", csosn)
        else:
            group = etree.SubElement(icms, f"{{{NFE_NS}}}ICMS00")
            _text(group, "orig", origin)
            _text(group, "CST", tax_profile.cst if product else "00")
            _text(group, "modBC", "3")
            _text(group, "vBC", _money(line_total))
            _text(group, "pICMS", _money(tax_profile.icms_rate if product else 0))
            _text(group, "vICMS", "0.00")
        pis = etree.SubElement(imposto, f"{{{NFE_NS}}}PIS")
        pisnt = etree.SubElement(pis, f"{{{NFE_NS}}}PISNT")
        _text(pisnt, "CST", "07")
        cofins = etree.SubElement(imposto, f"{{{NFE_NS}}}COFINS")
        cofinsnt = etree.SubElement(cofins, f"{{{NFE_NS}}}COFINSNT")
        _text(cofinsnt, "CST", "07")
        rtc_totals._current_selective_value = append_item_selective_tax(
            imposto, fiscal_tax_product, line_total, item.quantity, item.unit, rtc_totals
        )
        append_item_ibscbs(
            imposto,
            fiscal_tax_product,
            line_total,
            rtc_totals,
            rtc_required=rtc_required,
            issue_date=issued_at.date(),
        )
        rtc_totals._current_selective_value = Decimal("0")

    total = etree.SubElement(inf, f"{{{NFE_NS}}}total")
    icmstot = etree.SubElement(total, f"{{{NFE_NS}}}ICMSTot")
    for tag, value in [
        ("vBC", "0.00"),
        ("vICMS", "0.00"),
        ("vICMSDeson", "0.00"),
        ("vFCP", "0.00"),
        ("vBCST", "0.00"),
        ("vST", "0.00"),
        ("vFCPST", "0.00"),
        ("vFCPSTRet", "0.00"),
        ("vProd", _money(total_products)),
        ("vFrete", "0.00"),
        ("vSeg", "0.00"),
        ("vDesc", _money(total_discount)),
        ("vII", "0.00"),
        ("vIPI", "0.00"),
        ("vIPIDevol", "0.00"),
        ("vPIS", "0.00"),
        ("vCOFINS", "0.00"),
        ("vOutro", "0.00"),
        ("vNF", _money(sale.total_amount)),
    ]:
        _text(icmstot, tag, value)
    append_ibscbs_totals(total, rtc_totals, sale.total_amount)

    transp = etree.SubElement(inf, f"{{{NFE_NS}}}transp")
    _text(transp, "modFrete", "9")
    pag = etree.SubElement(inf, f"{{{NFE_NS}}}pag")
    for payment in sale.payments:
        det_pag = etree.SubElement(pag, f"{{{NFE_NS}}}detPag")
        _text(det_pag, "indPag", _payment_indicator(document))
        method = {
            "dinheiro": "01",
            "cartao_credito": "03",
            "credito": "03",
            "cartao_debito": "04",
            "debito": "04",
            "pix": "17",
        }.get(payment.method, "99")
        _text(det_pag, "tPag", method)
        if method == "99":
            _text(det_pag, "xPag", (payment.method or "OUTROS").replace("_", " ").upper()[:60])
        _text(det_pag, "vPag", _money(payment.amount))
        _append_card_group(det_pag, method, payment.authorization_code)
    if Decimal(sale.change_amount or 0) > 0:
        _text(pag, "vTroco", _money(sale.change_amount))
    inf_adic = etree.SubElement(inf, f"{{{NFE_NS}}}infAdic")
    _text(
        inf_adic,
        "infCpl",
        _additional_info(
            document,
            (
                "NFC-e emitida em contingencia offline pelo Lyncar. "
                "Transmitir para a SEFAZ assim que a conexao voltar."
                if emission_type == "9"
                else (
                    "NFC-e emitida pelo Lyncar em ambiente de homologacao."
                    if tp_amb == "2"
                    else "NFC-e emitida pelo Lyncar."
                )
            ),
        ),
    )

    xml = etree.tostring(nfe, encoding="unicode", xml_declaration=False)
    return xml, access_key, issued_at


def _append_nfce_supplement(root: etree._Element, setting: CompanyFiscalSetting) -> None:
    inf = root.find(f"{{{NFE_NS}}}infNFe")
    signature = root.find("{http://www.w3.org/2000/09/xmldsig#}Signature")
    if inf is None or signature is None:
        raise NfceValidationError("XML NFC-e assinado sem dados para QR Code.")
    access_key = (inf.attrib.get("Id") or "").replace("NFe", "", 1)
    tp_amb = inf.findtext(f"{{{NFE_NS}}}ide/{{{NFE_NS}}}tpAmb") or "2"
    tp_emis = inf.findtext(f"{{{NFE_NS}}}ide/{{{NFE_NS}}}tpEmis") or "1"
    if tp_emis in {"1", "3", "4"}:
        qr_code = f"{NFCE_SP_URLS[setting.environment]['qrcode']}?p={access_key}|3|{tp_amb}"
    else:
        issued_at_text = inf.findtext(f"{{{NFE_NS}}}ide/{{{NFE_NS}}}dhEmi") or ""
        day = issued_at_text[8:10] if len(issued_at_text) >= 10 else "01"
        v_nf = inf.findtext(f"{{{NFE_NS}}}total/{{{NFE_NS}}}ICMSTot/{{{NFE_NS}}}vNF") or "0.00"
        cpf = inf.findtext(f"{{{NFE_NS}}}dest/{{{NFE_NS}}}CPF") or ""
        cnpj = inf.findtext(f"{{{NFE_NS}}}dest/{{{NFE_NS}}}CNPJ") or ""
        if cnpj:
            recipient_type = "1"
            recipient_id = cnpj
        elif cpf:
            recipient_type = "2"
            recipient_id = cpf
        else:
            recipient_type = ""
            recipient_id = ""
        qr_base = f"{access_key}|3|{tp_amb}|{day}|{v_nf}|{recipient_type}|{recipient_id}"
        _, _, key_pem, _ = _load_certificate(setting)
        private_key = serialization.load_pem_private_key(key_pem, password=None)
        signature_value = private_key.sign(
            qr_base.encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA1(),
        )
        qr_signature = base64.b64encode(signature_value).decode("ascii")
        qr_base = f"{qr_base}|{qr_signature}"
        qr_code = f"{NFCE_SP_URLS[setting.environment]['qrcode']}?p={qr_base}"
    existing = root.find(f"{{{NFE_NS}}}infNFeSupl")
    if existing is not None:
        root.remove(existing)
    supl = etree.Element(f"{{{NFE_NS}}}infNFeSupl")
    _text(supl, "qrCode", qr_code)
    _text(supl, "urlChave", NFCE_SP_URLS[setting.environment]["consulta"])
    root.insert(list(root).index(signature), supl)


def sign_nfe_root(
    root: etree._Element,
    setting: CompanyFiscalSetting,
    *,
    append_nfce_supplement: bool = False,
) -> None:
    _, _, key_pem, cert_pem = _load_certificate(setting)
    inf = root.find(f"{{{NFE_NS}}}infNFe")
    if inf is None:
        raise NfceValidationError("XML fiscal sem infNFe.")
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
    if append_nfce_supplement:
        _append_nfce_supplement(root, setting)


def sign_nfce_xml(xml: str, setting: CompanyFiscalSetting) -> str:
    root = etree.fromstring(xml.encode("utf-8"))
    sign_nfe_root(root, setting, append_nfce_supplement=True)
    return etree.tostring(root, encoding="unicode", xml_declaration=False)


def build_signed_nfce_envelope(xml_source: str, setting: CompanyFiscalSetting) -> tuple[str, str]:
    lot_id = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(body, f"{{{NFE_AUTORIZACAO_WSDL_NS}}}nfeDadosMsg", nsmap={None: NFE_AUTORIZACAO_WSDL_NS})
    batch = etree.SubElement(msg, f"{{{NFE_NS}}}enviNFe", versao="4.00", nsmap={None: NFE_NS})
    etree.SubElement(batch, f"{{{NFE_NS}}}idLote").text = lot_id
    etree.SubElement(batch, f"{{{NFE_NS}}}indSinc").text = "1"
    signed_xml = sign_nfce_xml(xml_source, setting)
    nfe_root = etree.fromstring(signed_xml.encode("utf-8"))
    batch.append(nfe_root)
    envelope_xml = etree.tostring(
        envelope,
        encoding="utf-8",
        xml_declaration=False,
        pretty_print=False,
    ).decode("utf-8")
    return signed_xml, envelope_xml


def send_nfce_authorization(signed_xml: str, setting: CompanyFiscalSetting, envelope_xml: str | None = None) -> NfceResult:
    raw_cert, password, _, _ = _load_certificate(setting)
    if envelope_xml is None:
        lot_id = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
        body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
        msg = etree.SubElement(body, f"{{{NFE_AUTORIZACAO_WSDL_NS}}}nfeDadosMsg", nsmap={None: NFE_AUTORIZACAO_WSDL_NS})
        batch = etree.SubElement(msg, f"{{{NFE_NS}}}enviNFe", versao="4.00", nsmap={None: NFE_NS})
        etree.SubElement(batch, f"{{{NFE_NS}}}idLote").text = lot_id
        etree.SubElement(batch, f"{{{NFE_NS}}}indSinc").text = "1"
        batch.append(etree.fromstring(signed_xml.encode("utf-8")))
        envelope_xml = etree.tostring(
            envelope,
            encoding="utf-8",
            xml_declaration=False,
            pretty_print=False,
        ).decode("utf-8")
    response = requests_pkcs12.post(
        NFCE_SP_URLS[setting.environment]["autorizacao"],
        data=envelope_xml.encode("utf-8"),
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{NFE_AUTORIZACAO_ACTION}"',
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    root = etree.fromstring(response.content)
    text = etree.tostring(root, encoding="unicode")
    protocol_node = root.find(f".//{{{NFE_NS}}}protNFe/{{{NFE_NS}}}infProt")
    if protocol_node is not None:
        cstat = protocol_node.findtext(f"{{{NFE_NS}}}cStat")
        xmotivo = protocol_node.findtext(f"{{{NFE_NS}}}xMotivo") or "Retorno SEFAZ sem mensagem."
        protocol = protocol_node.findtext(f"{{{NFE_NS}}}nProt")
    else:
        cstat = root.findtext(f".//{{{NFE_NS}}}cStat")
        xmotivo = root.findtext(f".//{{{NFE_NS}}}xMotivo") or "Retorno SEFAZ sem mensagem."
        protocol = root.findtext(f".//{{{NFE_NS}}}nProt")
    if cstat in {"100", "150"}:
        return NfceResult(
            "authorized",
            cstat,
            xmotivo,
            protocol=protocol,
            authorized_xml=build_processed_nfe_xml(signed_xml, text),
        )
    return NfceResult("rejected", cstat, xmotivo, authorized_xml=text)


def authorize_nfce(setting: CompanyFiscalSetting, document: FiscalDocument, sale: Sale) -> NfceResult:
    xml, access_key, issued_at = build_nfce_xml(setting, document, sale)
    document.xml_generated = xml
    document.access_key = access_key
    document.issued_at = issued_at
    signed_xml = sign_nfce_xml(xml, setting)
    document.xml_signed = signed_xml
    return send_nfce_authorization(signed_xml, setting)


def prepare_nfce_offline_contingency(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    sale: Sale,
) -> NfceResult:
    xml, access_key, issued_at = build_nfce_xml(setting, document, sale, emission_type="9")
    document.xml_generated = xml
    document.access_key = access_key
    document.issued_at = issued_at
    signed_xml = sign_nfce_xml(xml, setting)
    document.xml_signed = signed_xml
    return NfceResult(
        "contingency_offline",
        "CONTINGENCIA_OFFLINE",
        "NFC-e emitida em contingencia offline. Transmita para a SEFAZ assim que a conexao voltar.",
    )


def transmit_nfce_offline_contingency(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
) -> NfceResult:
    if not document.xml_signed:
        raise NfceValidationError("NFC-e em contingencia sem XML assinado para transmissao.")
    return send_nfce_authorization(document.xml_signed, setting)

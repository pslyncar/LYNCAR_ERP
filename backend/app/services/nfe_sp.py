from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from random import randint

import requests_pkcs12
from lxml import etree

from app.core.config import get_settings
from app.models.fiscal import CompanyFiscalSetting, FiscalDocument
from app.models.sale import Sale
from app.services.fiscal_output_rules import apply_draft_tax_overrides, product_with_output_tax_profile, resolve_output_tax_profile
from app.services.fiscal_document_policy import assert_supported_authorizer
from app.services.fiscal_xml import build_processed_nfe_xml
from app.services.holidays import _resolve_ibge_city_code
from app.services.nfce_sp import (
    NFE_AUTORIZACAO_ACTION,
    NFE_AUTORIZACAO_WSDL_NS,
    NFE_NS,
    SOAP_NS,
    NfceResult,
    NfceValidationError,
    _check_digit,
    _digits,
    _gtin_or_sem_gtin,
    _load_certificate,
    _money,
    _quantity,
    _effective_csosn,
    _effective_crt,
    _require_sale,
    _text,
    sign_nfe_root,
)
from app.services.rtc_tax import RtcTaxTotals, append_ibscbs_totals, append_item_ibscbs, append_item_selective_tax
from app.services.rtc_compliance import is_rtc_mandatory

SP_UF_CODE = "35"
NFE_SP_URLS = {
    "homologacao": {
        "autorizacao": "https://homologacao.nfe.fazenda.sp.gov.br/ws/nfeautorizacao4.asmx",
        "evento": "https://homologacao.nfe.fazenda.sp.gov.br/ws/nferecepcaoevento4.asmx",
    },
    "producao": {
        "autorizacao": "https://nfe.fazenda.sp.gov.br/ws/nfeautorizacao4.asmx",
        "evento": "https://nfe.fazenda.sp.gov.br/ws/nferecepcaoevento4.asmx",
    },
}

_DUPLICATE_NFE_KEY_PATTERN = re.compile(r"chNFe\s*:\s*(\d{44})")


def _duplicate_nfe_key(message: str | None) -> str | None:
    match = _DUPLICATE_NFE_KEY_PATTERN.search(message or "")
    return match.group(1) if match else None


def _weight(value: Decimal | int | float | None) -> str:
    amount = Decimal(value or 0).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
    return f"{amount:.3f}"


def _allocate_line_amounts(
    total: Decimal | int | float | None,
    weights: list[Decimal],
) -> list[Decimal]:
    """Rateia um total monetario garantindo que os centavos fechem exatamente."""
    if not weights:
        return []
    amount = max(Decimal(total or 0), Decimal("0")).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )
    if amount == 0:
        return [Decimal("0.00") for _ in weights]
    normalized = [max(Decimal(weight or 0), Decimal("0")) for weight in weights]
    weight_total = sum(normalized, Decimal("0"))
    if weight_total == 0:
        normalized = [Decimal("1") for _ in weights]
        weight_total = Decimal(len(weights))
    total_cents = int(amount * 100)
    raw_cents = [Decimal(total_cents) * weight / weight_total for weight in normalized]
    allocated_cents = [int(value) for value in raw_cents]
    remaining = total_cents - sum(allocated_cents)
    priority = sorted(
        range(len(raw_cents)),
        key=lambda index: (raw_cents[index] - allocated_cents[index], -index),
        reverse=True,
    )
    for index in priority[:remaining]:
        allocated_cents[index] += 1
    return [Decimal(cents) / Decimal("100") for cents in allocated_cents]


def _require_setting(setting: CompanyFiscalSetting) -> None:
    assert_supported_authorizer(setting, model="55")
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
        raise NfceValidationError(
            "Complete a configuracao fiscal para NF-e: " + ", ".join(missing) + "."
        )


def _recipient_city_code(sale: Sale) -> str:
    client = sale.client
    if client is None or not client.city or not client.state:
        raise NfceValidationError("A NF-e exige cliente com cidade e UF cadastradas.")
    if getattr(client, "city_code", None):
        return _digits(client.city_code)
    code = _resolve_ibge_city_code(client.city, client.state)
    if code is None:
        raise NfceValidationError(
            "Nao foi possivel localizar o codigo IBGE da cidade do cliente."
        )
    return str(code)


def _require_recipient(sale: Sale) -> None:
    client = sale.client
    if client is None:
        raise NfceValidationError("A NF-e modelo 55 exige cliente vinculado a venda.")
    missing = []
    for label, value in [
        ("nome/razao social", client.name),
        ("CPF/CNPJ", client.document_number),
        ("logradouro", client.address),
        ("numero", client.address_number),
        ("bairro", client.neighborhood),
        ("cidade", client.city),
        ("UF", client.state),
        ("CEP", client.zip_code),
    ]:
        if not value:
            missing.append(label)
    document = _digits(client.document_number)
    if len(document) not in {11, 14}:
        missing.append("CPF/CNPJ valido")
    if missing:
        raise NfceValidationError(
            "Complete o cadastro do cliente para NF-e: " + ", ".join(missing) + "."
        )


def _access_key(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    issued_at: datetime,
    random_code: str,
) -> str:
    base = (
        SP_UF_CODE
        + issued_at.strftime("%y%m")
        + _digits(setting.cnpj).zfill(14)
        + "55"
        + f"{int(document.series or setting.nfe_series or 1):03d}"
        + f"{int(document.number or setting.nfe_next_number or 1):09d}"
        + "1"
        + random_code.zfill(8)
    )
    return base + _check_digit(base)


def _operation_nature(document: FiscalDocument) -> str:
    return " ".join((document.operation_nature or "").split())[:60] or "VENDA DE MERCADORIA"


def _payment_indicator(document: FiscalDocument) -> str:
    return "1" if document.payment_condition == "prazo" else "0"


def _recipient_ie_indicator(client) -> str:
    indicator = str(getattr(client, "tax_contributor_type", "") or "").strip().lower()
    if indicator in {"1", "contribuinte", "icms"}:
        return "1"
    if indicator in {"2", "isento"}:
        return "2"
    if indicator in {"9", "nao_contribuinte", "não_contribuinte", "consumidor"}:
        return "9"
    return "1" if getattr(client, "state_registration", None) else "9"


def _additional_info(document: FiscalDocument, default_text: str) -> str:
    notes = " ".join((document.fiscal_notes or "").split())
    if notes:
        return f"{default_text} {notes}"[:5000]
    return default_text


def _append_card_group(det_pag: etree._Element, method: str, authorization_code: str | None) -> None:
    """Informa grupo card para cartao/PIX quando a SEFAZ exige dados do pagamento."""
    if method not in {"03", "04", "17"}:
        return
    card = etree.SubElement(det_pag, f"{{{NFE_NS}}}card")
    _text(card, "tpIntegra", "2")
    if authorization_code:
        _text(card, "cAut", authorization_code[:20])


def build_nfe_xml(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    sale: Sale,
) -> tuple[str, str, datetime]:
    _require_setting(setting)
    _require_sale(sale, setting, model="55")
    _require_recipient(sale)
    client = sale.client
    assert client is not None

    issued_at = datetime.now(timezone(timedelta(hours=-3)))
    rtc_required = is_rtc_mandatory(setting, issued_at.date())
    random_code = str(randint(1, 99999999)).zfill(8)
    document.series = document.series or int(setting.nfe_series or 1)
    document.number = document.number or int(setting.nfe_next_number or 1)
    access_key = _access_key(setting, document, issued_at, random_code)
    tp_amb = "2" if setting.environment == "homologacao" else "1"
    destination_state = (client.state or "").upper()

    nfe = etree.Element(f"{{{NFE_NS}}}NFe", nsmap={None: NFE_NS})
    inf = etree.SubElement(
        nfe,
        f"{{{NFE_NS}}}infNFe",
        versao="4.00",
        Id=f"NFe{access_key}",
    )
    ide = etree.SubElement(inf, f"{{{NFE_NS}}}ide")
    for tag, value in [
        ("cUF", SP_UF_CODE),
        ("cNF", random_code),
        ("natOp", _operation_nature(document)),
        ("mod", "55"),
        ("serie", document.series),
        ("nNF", document.number),
        ("dhEmi", issued_at.isoformat(timespec="seconds")),
        ("tpNF", "1"),
        ("idDest", "1" if destination_state == "SP" else "2"),
        ("cMunFG", _digits(setting.city_code)),
        ("tpImp", "1"),
        ("tpEmis", "1"),
        ("cDV", access_key[-1]),
        ("tpAmb", tp_amb),
        ("finNFe", document.finality or "1"),
        ("indFinal", "1"),
        ("indPres", "1"),
        ("procEmi", "0"),
        ("verProc", "Lyncar-1.0"),
    ]:
        _text(ide, tag, value)

    emit = etree.SubElement(inf, f"{{{NFE_NS}}}emit")
    _text(emit, "CNPJ", _digits(setting.cnpj).zfill(14))
    _text(emit, "xNome", setting.legal_name)
    if setting.trade_name:
        _text(emit, "xFant", setting.trade_name)
    ender_emit = etree.SubElement(emit, f"{{{NFE_NS}}}enderEmit")
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
        _text(ender_emit, tag, value)
    _text(emit, "IE", _digits(setting.state_registration))
    _text(emit, "CRT", _effective_crt(setting))

    recipient_document = _digits(client.document_number)
    dest = etree.SubElement(inf, f"{{{NFE_NS}}}dest")
    _text(dest, "CNPJ" if len(recipient_document) == 14 else "CPF", recipient_document)
    _text(
        dest,
        "xNome",
        "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
        if tp_amb == "2"
        else client.name,
    )
    ender_dest = etree.SubElement(dest, f"{{{NFE_NS}}}enderDest")
    for tag, value in [
        ("xLgr", client.address),
        ("nro", client.address_number),
        ("xCpl", client.address_complement),
        ("xBairro", client.neighborhood),
        ("cMun", _recipient_city_code(sale)),
        ("xMun", client.city),
        ("UF", destination_state),
        ("CEP", _digits(client.zip_code)),
        ("cPais", _digits(getattr(client, "country_code", None)) or "1058"),
        ("xPais", getattr(client, "country_name", None) or "BRASIL"),
    ]:
        if value:
            _text(ender_dest, tag, value)
    ind_ie_dest = _recipient_ie_indicator(client)
    _text(dest, "indIEDest", ind_ie_dest)
    if ind_ie_dest == "1" and client.state_registration:
        _text(dest, "IE", _digits(client.state_registration))
    if getattr(client, "suframa", None):
        _text(dest, "ISUF", _digits(client.suframa))
    if client.email:
        _text(dest, "email", client.email)

    sale_items = list(sale.items)
    allocation_weights = [
        max(Decimal(item.quantity or 0) * Decimal(item.unit_price or 0), Decimal("0"))
        for item in sale_items
    ]
    freight_by_item = _allocate_line_amounts(document.freight_amount, allocation_weights)
    insurance_by_item = _allocate_line_amounts(document.insurance_amount, allocation_weights)
    other_expenses_by_item = _allocate_line_amounts(
        document.other_expenses_amount,
        allocation_weights,
    )
    total_products = Decimal("0")
    total_discount = Decimal("0")
    rtc_totals = RtcTaxTotals()
    for index, item in enumerate(sale_items, start=1):
        product = item.product
        quantity = Decimal(item.quantity or 0)
        unit_price = Decimal(item.unit_price or 0)
        line_total = quantity * unit_price
        total_products += line_total
        total_discount += Decimal(item.discount_amount or 0)

        det = etree.SubElement(inf, f"{{{NFE_NS}}}det", nItem=str(index))
        prod = etree.SubElement(det, f"{{{NFE_NS}}}prod")
        tax_profile = resolve_output_tax_profile(
            setting,
            product,
            model="55",
            uf_destination=destination_state,
        )
        tax_profile = apply_draft_tax_overrides(tax_profile, item)
        for tag, value in [
            (
                "cProd",
                product.internal_code
                if product and product.internal_code
                else item.product_id or index,
            ),
            ("cEAN", _gtin_or_sem_gtin(item.barcode)),
            (
                "xProd",
                "NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
                if tp_amb == "2"
                else item.description,
            ),
            ("NCM", _digits(getattr(item, "ncm", None) or (product.ncm if product else ""))),
        ]:
            _text(prod, tag, value)
        cest = _digits(getattr(item, "cest", None) or (getattr(product, "cest", None) if product else ""))
        if len(cest) == 7:
            _text(prod, "CEST", cest)
        cbenef = (getattr(item, "cbenef", None) or "").strip()
        if cbenef:
            _text(prod, "cBenef", cbenef)
        for tag, value in [
            ("CFOP", tax_profile.cfop if product else ""),
            ("uCom", (item.unit or "UN").upper()[:6]),
            ("qCom", _quantity(quantity)),
            ("vUnCom", _money(unit_price)),
            ("vProd", _money(line_total)),
            ("cEANTrib", _gtin_or_sem_gtin(item.barcode)),
            ("uTrib", (item.unit or "UN").upper()[:6]),
            ("qTrib", _quantity(quantity)),
            ("vUnTrib", _money(unit_price)),
        ]:
            _text(prod, tag, value)
        if freight_by_item[index - 1] > 0:
            _text(prod, "vFrete", _money(freight_by_item[index - 1]))
        if insurance_by_item[index - 1] > 0:
            _text(prod, "vSeg", _money(insurance_by_item[index - 1]))
        if Decimal(item.discount_amount or 0) > 0:
            _text(prod, "vDesc", _money(item.discount_amount))
        if other_expenses_by_item[index - 1] > 0:
            _text(prod, "vOutro", _money(other_expenses_by_item[index - 1]))
        _text(prod, "indTot", "1")

        imposto = etree.SubElement(det, f"{{{NFE_NS}}}imposto")
        icms = etree.SubElement(imposto, f"{{{NFE_NS}}}ICMS")
        csosn = tax_profile.csosn
        fiscal_tax_product = product_with_output_tax_profile(product, tax_profile)
        if csosn:
            group = etree.SubElement(icms, f"{{{NFE_NS}}}ICMSSN102")
            _text(group, "orig", tax_profile.origin or "0")
            _text(group, "CSOSN", csosn)
        else:
            group = etree.SubElement(icms, f"{{{NFE_NS}}}ICMS00")
            _text(group, "orig", tax_profile.origin if product else "0")
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
        ("vFrete", _money(document.freight_amount or 0)),
        ("vSeg", _money(document.insurance_amount or 0)),
        ("vDesc", _money(total_discount)),
        ("vII", "0.00"),
        ("vIPI", "0.00"),
        ("vIPIDevol", "0.00"),
        ("vPIS", "0.00"),
        ("vCOFINS", "0.00"),
        ("vOutro", _money(document.other_expenses_amount or 0)),
        ("vNF", _money(Decimal(sale.total_amount or 0) + Decimal(document.freight_amount or 0) + Decimal(document.insurance_amount or 0) + Decimal(document.other_expenses_amount or 0))),
    ]:
        _text(icmstot, tag, value)
    append_ibscbs_totals(total, rtc_totals, sale.total_amount)

    transp = etree.SubElement(inf, f"{{{NFE_NS}}}transp")
    _text(transp, "modFrete", document.freight_mode or "9")
    if document.carrier_name:
        transporta = etree.SubElement(transp, f"{{{NFE_NS}}}transporta")
        carrier_document = _digits(document.carrier_document or "")
        if len(carrier_document) == 14:
            _text(transporta, "CNPJ", carrier_document)
        elif len(carrier_document) == 11:
            _text(transporta, "CPF", carrier_document)
        _text(transporta, "xNome", document.carrier_name)
        carrier_ie = _digits(document.carrier_state_registration or "")
        if carrier_ie:
            _text(transporta, "IE", carrier_ie)
        _text(transporta, "xEnder", document.carrier_address)
        _text(transporta, "xMun", document.carrier_city)
        _text(transporta, "UF", document.carrier_uf)
    if document.volume_quantity is not None or document.net_weight is not None or document.gross_weight is not None:
        vol = etree.SubElement(transp, f"{{{NFE_NS}}}vol")
        _text(vol, "qVol", int(Decimal(document.volume_quantity or 0)))
        _text(vol, "esp", document.volume_species)
        _text(vol, "marca", document.volume_brand)
        _text(vol, "nVol", document.volume_numbering)
        _text(vol, "pesoL", _weight(document.net_weight or 0))
        _text(vol, "pesoB", _weight(document.gross_weight or 0))
    pag = etree.SubElement(inf, f"{{{NFE_NS}}}pag")
    payments = list(sale.payments)
    fiscal_additions = (
        Decimal(document.freight_amount or 0)
        + Decimal(document.insurance_amount or 0)
        + Decimal(document.other_expenses_amount or 0)
    )
    for payment_index, payment in enumerate(payments):
        det_pag = etree.SubElement(pag, f"{{{NFE_NS}}}detPag")
        method = {
            "dinheiro": "01",
            "cartao_credito": "03",
            "credito": "03",
            "cartao_debito": "04",
            "debito": "04",
            "pix": "17",
            "boleto": "15",
            "transferencia": "18",
            "crediario": "05",
        }.get(payment.method, "99")
        _text(det_pag, "indPag", _payment_indicator(document))
        _text(det_pag, "tPag", method)
        if method == "99":
            _text(det_pag, "xPag", (payment.method or "OUTROS").upper()[:60])
        payment_amount = Decimal(payment.amount or 0)
        if payment_index == len(payments) - 1:
            payment_amount += fiscal_additions
        _text(det_pag, "vPag", _money(payment_amount))
        _append_card_group(det_pag, method, payment.authorization_code)
    if Decimal(getattr(sale, "change_amount", 0) or 0) > 0:
        _text(pag, "vTroco", _money(sale.change_amount))

    inf_adic = etree.SubElement(inf, f"{{{NFE_NS}}}infAdic")
    _text(
        inf_adic,
        "infCpl",
        _additional_info(
            document,
            "NF-e emitida pelo Lyncar em ambiente de homologacao."
            if tp_amb == "2"
            else "NF-e emitida pelo Lyncar.",
        ),
    )
    return (
        etree.tostring(nfe, encoding="unicode", xml_declaration=False),
        access_key,
        issued_at,
    )


def sign_nfe_xml(xml: str, setting: CompanyFiscalSetting) -> str:
    root = etree.fromstring(xml.encode("utf-8"))
    sign_nfe_root(root, setting)
    return etree.tostring(root, encoding="unicode", xml_declaration=False)


def send_nfe_authorization(
    signed_xml: str,
    setting: CompanyFiscalSetting,
) -> NfceResult:
    raw_cert, password, _, _ = _load_certificate(setting)
    envelope = etree.Element(f"{{{SOAP_NS}}}Envelope", nsmap={"soap12": SOAP_NS})
    body = etree.SubElement(envelope, f"{{{SOAP_NS}}}Body")
    msg = etree.SubElement(
        body,
        f"{{{NFE_AUTORIZACAO_WSDL_NS}}}nfeDadosMsg",
        nsmap={None: NFE_AUTORIZACAO_WSDL_NS},
    )
    batch = etree.SubElement(
        msg,
        f"{{{NFE_NS}}}enviNFe",
        versao="4.00",
        nsmap={None: NFE_NS},
    )
    etree.SubElement(batch, f"{{{NFE_NS}}}idLote").text = datetime.utcnow().strftime(
        "%Y%m%d%H%M%S"
    )
    etree.SubElement(batch, f"{{{NFE_NS}}}indSinc").text = "1"
    batch.append(etree.fromstring(signed_xml.encode("utf-8")))
    payload = etree.tostring(envelope, encoding="utf-8", pretty_print=False)

    response = requests_pkcs12.post(
        NFE_SP_URLS[setting.environment]["autorizacao"],
        data=payload,
        pkcs12_data=raw_cert,
        pkcs12_password=password,
        headers={
            "Content-Type": (
                'application/soap+xml; charset=utf-8; '
                f'action="{NFE_AUTORIZACAO_ACTION}"'
            ),
        },
        verify=get_settings().sefaz_tls_verify,
        timeout=get_settings().sefaz_timeout_seconds,
    )
    response.raise_for_status()
    root = etree.fromstring(response.content)
    response_xml = etree.tostring(root, encoding="unicode")
    protocol_node = root.find(f".//{{{NFE_NS}}}protNFe/{{{NFE_NS}}}infProt")
    if protocol_node is not None:
        cstat = protocol_node.findtext(f"{{{NFE_NS}}}cStat")
        message = (
            protocol_node.findtext(f"{{{NFE_NS}}}xMotivo")
            or "Retorno SEFAZ sem mensagem."
        )
        protocol = protocol_node.findtext(f"{{{NFE_NS}}}nProt")
    else:
        cstat = root.findtext(f".//{{{NFE_NS}}}cStat")
        message = (
            root.findtext(f".//{{{NFE_NS}}}xMotivo")
            or "Retorno SEFAZ sem mensagem."
        )
        protocol = root.findtext(f".//{{{NFE_NS}}}nProt")
    if cstat in {"100", "150"}:
        return NfceResult(
            "authorized",
            cstat,
            message,
            protocol=protocol,
            authorized_xml=build_processed_nfe_xml(signed_xml, response_xml),
        )
    return NfceResult("rejected", cstat, message, authorized_xml=response_xml)


def authorize_nfe(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
    sale: Sale,
) -> NfceResult:
    xml, access_key, issued_at = build_nfe_xml(setting, document, sale)
    document.xml_generated = xml
    document.access_key = access_key
    document.issued_at = issued_at
    signed_xml = sign_nfe_xml(xml, setting)
    document.xml_signed = signed_xml
    return send_nfe_authorization(signed_xml, setting)

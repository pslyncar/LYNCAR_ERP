from decimal import Decimal
import xml.etree.ElementTree as ET


def _text(parent: ET.Element, path: str) -> str | None:
    element = parent.find(path)
    if element is None or element.text is None:
        return None
    value = element.text.strip()
    return value or None


def _decimal(value: str | None) -> Decimal:
    if not value:
        return Decimal("0")
    return Decimal(value.replace(",", "."))


def _first_child(parent: ET.Element | None) -> ET.Element | None:
    if parent is None:
        return None
    return next(iter(parent), None)


def _first_tax_group(parent: ET.Element | None, ns: str, tag: str) -> ET.Element | None:
    group = parent.find(f"{ns}{tag}") if parent is not None else None
    return _first_child(group)


def parse_nfe_xml(xml_content: str) -> dict[str, object]:
    try:
        root = ET.fromstring(xml_content.encode("utf-8"))
    except ET.ParseError as exc:
        raise ValueError("XML da NF-e invalido.") from exc

    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag.split("}", 1)[0] + "}"

    inf_nfe = root.find(f".//{ns}infNFe")
    if inf_nfe is None:
        raise ValueError("Nao foi encontrado o bloco infNFe no XML.")

    ide = inf_nfe.find(f"{ns}ide")
    emit = inf_nfe.find(f"{ns}emit")
    dest = inf_nfe.find(f"{ns}dest")
    supplier_name = _text(emit, f"{ns}xNome") if emit is not None else None
    supplier_document = (
        _text(emit, f"{ns}CNPJ") or _text(emit, f"{ns}CPF")
        if emit is not None
        else None
    )
    recipient_name = _text(dest, f"{ns}xNome") if dest is not None else None
    recipient_document = (
        _text(dest, f"{ns}CNPJ") or _text(dest, f"{ns}CPF")
        if dest is not None
        else None
    )
    invoice_key = inf_nfe.attrib.get("Id", "").replace("NFe", "") or None

    items: list[dict[str, object]] = []
    for det in inf_nfe.findall(f"{ns}det"):
        prod = det.find(f"{ns}prod")
        if prod is None:
            continue
        quantity = _decimal(_text(prod, f"{ns}qCom"))
        total = _decimal(_text(prod, f"{ns}vProd"))
        xml_unit_cost = _decimal(_text(prod, f"{ns}vUnCom"))
        unit_cost = (
            xml_unit_cost
            if xml_unit_cost > 0
            else (total / quantity if quantity > 0 else Decimal("0"))
        )
        barcode = _text(prod, f"{ns}cEAN")
        if barcode in {None, "SEM GTIN"}:
            barcode = _text(prod, f"{ns}cProd")
        rastro = prod.find(f"{ns}rastro")
        imposto = det.find(f"{ns}imposto")
        icms_group = _first_tax_group(imposto, ns, "ICMS")
        pis_group = _first_tax_group(imposto, ns, "PIS")
        cofins_group = _first_tax_group(imposto, ns, "COFINS")
        ipi_group = imposto.find(f"{ns}IPI/{ns}IPITrib") if imposto is not None else None
        ibscbs = imposto.find(f"{ns}IBSCBS") if imposto is not None else None
        ibscbs_group = ibscbs.find(f"{ns}gIBSCBS") if ibscbs is not None else None
        ibs_uf = ibscbs_group.find(f"{ns}gIBSUF") if ibscbs_group is not None else None
        ibs_mun = ibscbs_group.find(f"{ns}gIBSMun") if ibscbs_group is not None else None
        cbs = ibscbs_group.find(f"{ns}gCBS") if ibscbs_group is not None else None
        selective = imposto.find(f"{ns}IS") if imposto is not None else None
        items.append(
            {
                "description": _text(prod, f"{ns}xProd") or "Produto NF-e",
                "barcode": barcode,
                "quantity": quantity,
                "unit": (_text(prod, f"{ns}uCom") or "un").lower(),
                "unit_cost": unit_cost,
                "total_cost": total,
                "ncm": _text(prod, f"{ns}NCM"),
                "cfop": _text(prod, f"{ns}CFOP"),
                "origin": _text(icms_group, f"{ns}orig") if icms_group is not None else None,
                "cst": _text(icms_group, f"{ns}CST") if icms_group is not None else None,
                "csosn": _text(icms_group, f"{ns}CSOSN") if icms_group is not None else None,
                "icms_rate": (
                    _decimal(_text(icms_group, f"{ns}pICMS"))
                    if icms_group is not None and _text(icms_group, f"{ns}pICMS") is not None
                    else None
                ),
                "pis_rate": (
                    _decimal(_text(pis_group, f"{ns}pPIS"))
                    if pis_group is not None and _text(pis_group, f"{ns}pPIS") is not None
                    else None
                ),
                "cofins_rate": (
                    _decimal(_text(cofins_group, f"{ns}pCOFINS"))
                    if cofins_group is not None and _text(cofins_group, f"{ns}pCOFINS") is not None
                    else None
                ),
                "ipi_rate": (
                    _decimal(_text(ipi_group, f"{ns}pIPI"))
                    if ipi_group is not None and _text(ipi_group, f"{ns}pIPI") is not None
                    else None
                ),
                "ibs_cbs_cst": _text(ibscbs, f"{ns}CST") if ibscbs is not None else None,
                "ibs_cbs_classification": (
                    _text(ibscbs, f"{ns}cClassTrib") if ibscbs is not None else None
                ),
                "cbs_rate": _decimal(_text(cbs, f"{ns}pCBS")) if cbs is not None else None,
                "ibs_state_rate": (
                    _decimal(_text(ibs_uf, f"{ns}pIBSUF")) if ibs_uf is not None else None
                ),
                "ibs_city_rate": (
                    _decimal(_text(ibs_mun, f"{ns}pIBSMun")) if ibs_mun is not None else None
                ),
                "selective_tax_rate": (
                    _decimal(_text(selective, f"{ns}pIS")) if selective is not None else None
                ),
                "selective_tax_cst": (
                    _text(selective, f"{ns}CSTIS") if selective is not None else None
                ),
                "selective_tax_classification": (
                    _text(selective, f"{ns}cClassTribIS") if selective is not None else None
                ),
                "batch_number": _text(rastro, f"{ns}nLote") if rastro is not None else None,
                "expiration_date": _text(rastro, f"{ns}dVal") if rastro is not None else None,
            }
        )

    if not items:
        raise ValueError("Nenhum produto foi encontrado no XML da NF-e.")

    return {
        "supplier_name": supplier_name,
        "supplier_document": supplier_document,
        "recipient_name": recipient_name,
        "recipient_document": recipient_document,
        "invoice_key": invoice_key,
        "invoice_number": _text(ide, f"{ns}nNF") if ide is not None else None,
        "invoice_series": _text(ide, f"{ns}serie") if ide is not None else None,
        "items": items,
    }

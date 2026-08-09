from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from typing import Any

from lxml import etree

from app.services.rtc_compliance import rtc_rates_for

NFE_NS = "http://www.portalfiscal.inf.br/nfe"


def _decimal(value: Any) -> Decimal:
    if value is None:
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value or "0"))


def _money(value: Any) -> str:
    return str(_decimal(value).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _rate(value: Any) -> str:
    return str(_decimal(value).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def _text(parent: etree._Element, tag: str, value: object | None) -> etree._Element:
    child = etree.SubElement(parent, f"{{{NFE_NS}}}{tag}")
    child.text = "" if value is None else str(value)
    return child


@dataclass
class RtcTaxTotals:
    selective_base: Decimal = Decimal("0")
    selective: Decimal = Decimal("0")
    base: Decimal = Decimal("0")
    ibs_uf: Decimal = Decimal("0")
    ibs_mun: Decimal = Decimal("0")
    ibs: Decimal = Decimal("0")
    cbs: Decimal = Decimal("0")


def product_has_rtc_tax(product: Any | None) -> bool:
    if product is None:
        return False
    return bool(
        getattr(product, "ibs_cbs_cst", None)
        and getattr(product, "ibs_cbs_classification", None)
    )


def product_has_selective_tax(product: Any | None) -> bool:
    return bool(
        product is not None
        and getattr(product, "new_tax_system", False)
        and getattr(product, "selective_tax_cst", None)
        and getattr(product, "selective_tax_classification", None)
        and _decimal(getattr(product, "selective_tax_rate", None)) > 0
    )


def append_item_selective_tax(
    imposto: etree._Element,
    product: Any | None,
    taxable_amount: Decimal,
    quantity: Decimal,
    unit: str | None,
    totals: RtcTaxTotals,
) -> Decimal:
    if not product_has_selective_tax(product):
        return Decimal("0")
    base = max(_decimal(taxable_amount), Decimal("0"))
    rate = _decimal(getattr(product, "selective_tax_rate", None))
    value = (base * rate / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    selective = etree.SubElement(imposto, f"{{{NFE_NS}}}IS")
    _text(selective, "CSTIS", getattr(product, "selective_tax_cst", None))
    _text(selective, "cClassTribIS", getattr(product, "selective_tax_classification", None))
    _text(selective, "vBCIS", _money(base))
    _text(selective, "pIS", _rate(rate))
    _text(selective, "pISEspec", "0.0000")
    _text(selective, "uTrib", (unit or "UN").upper()[:6])
    _text(selective, "qTrib", str(_decimal(quantity).quantize(Decimal("0.0001"))))
    _text(selective, "vIS", _money(value))
    totals.selective_base += base
    totals.selective += value
    return value


def append_item_ibscbs(
    imposto: etree._Element,
    product: Any | None,
    taxable_amount: Decimal,
    totals: RtcTaxTotals,
    *,
    rtc_required: bool = False,
    issue_date: date | None = None,
) -> None:
    """Append Grupo UB (IBS/CBS/IS) for NF-e/NFC-e item.

    This intentionally supports the standard/default taxation group first:
    /det/imposto/IBSCBS/CST, cClassTrib and gIBSCBS with IBS UF, IBS Mun and CBS.
    Other special groups (credit presumed, monophase, government purchase, ZFM/ALC)
    must be added later only when the product/operation has explicit data.
    """

    if not product_has_rtc_tax(product):
        return
    selective_value = _decimal(getattr(totals, "_current_selective_value", Decimal("0")))
    base = max(_decimal(taxable_amount) + selective_value, Decimal("0"))
    cst = getattr(product, "ibs_cbs_cst", None)
    classification = getattr(product, "ibs_cbs_classification", None)
    cbs_rate = _decimal(getattr(product, "cbs_rate", None))
    ibs_uf_rate = _decimal(getattr(product, "ibs_state_rate", None))
    ibs_mun_rate = _decimal(getattr(product, "ibs_city_rate", None))
    if rtc_required:
        rates = rtc_rates_for(issue_date or date.today())
        cbs_rate = rates.cbs
        ibs_uf_rate = rates.ibs_uf
        ibs_mun_rate = rates.ibs_mun
    ibs_uf_value = (base * ibs_uf_rate / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    ibs_mun_value = (base * ibs_mun_rate / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    ibs_value = ibs_uf_value + ibs_mun_value
    cbs_value = (base * cbs_rate / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )

    ibscbs = etree.SubElement(imposto, f"{{{NFE_NS}}}IBSCBS")
    _text(ibscbs, "CST", cst)
    _text(ibscbs, "cClassTrib", classification)
    standard = etree.SubElement(ibscbs, f"{{{NFE_NS}}}gIBSCBS")
    _text(standard, "vBC", _money(base))
    ibs_uf = etree.SubElement(standard, f"{{{NFE_NS}}}gIBSUF")
    _text(ibs_uf, "pIBSUF", _rate(ibs_uf_rate))
    _text(ibs_uf, "vIBSUF", _money(ibs_uf_value))
    ibs_mun = etree.SubElement(standard, f"{{{NFE_NS}}}gIBSMun")
    _text(ibs_mun, "pIBSMun", _rate(ibs_mun_rate))
    _text(ibs_mun, "vIBSMun", _money(ibs_mun_value))
    _text(standard, "vIBS", _money(ibs_value))
    cbs = etree.SubElement(standard, f"{{{NFE_NS}}}gCBS")
    _text(cbs, "pCBS", _rate(cbs_rate))
    _text(cbs, "vCBS", _money(cbs_value))

    totals.base += base
    totals.ibs_uf += ibs_uf_value
    totals.ibs_mun += ibs_mun_value
    totals.ibs += ibs_value
    totals.cbs += cbs_value


def append_ibscbs_totals(
    total: etree._Element,
    totals: RtcTaxTotals,
    document_total: Decimal | None = None,
) -> None:
    if totals.base <= 0 and totals.selective_base <= 0:
        return
    if totals.selective_base > 0:
        istot = etree.SubElement(total, f"{{{NFE_NS}}}ISTot")
        _text(istot, "vIS", _money(totals.selective))
    if totals.base <= 0:
        if document_total is not None:
            _text(total, "vNFTot", _money(_decimal(document_total) + totals.selective))
        return
    ibscbs_tot = etree.SubElement(total, f"{{{NFE_NS}}}IBSCBSTot")
    _text(ibscbs_tot, "vBCIBSCBS", _money(totals.base))
    ibs = etree.SubElement(ibscbs_tot, f"{{{NFE_NS}}}gIBS")
    ibs_uf = etree.SubElement(ibs, f"{{{NFE_NS}}}gIBSUF")
    _text(ibs_uf, "vDif", "0.00")
    _text(ibs_uf, "vDevTrib", "0.00")
    _text(ibs_uf, "vIBSUF", _money(totals.ibs_uf))
    ibs_mun = etree.SubElement(ibs, f"{{{NFE_NS}}}gIBSMun")
    _text(ibs_mun, "vDif", "0.00")
    _text(ibs_mun, "vDevTrib", "0.00")
    _text(ibs_mun, "vIBSMun", _money(totals.ibs_mun))
    _text(ibs, "vIBS", _money(totals.ibs))
    _text(ibs, "vCredPres", "0.00")
    _text(ibs, "vCredPresCondSus", "0.00")
    cbs = etree.SubElement(ibscbs_tot, f"{{{NFE_NS}}}gCBS")
    _text(cbs, "vDif", "0.00")
    _text(cbs, "vDevTrib", "0.00")
    _text(cbs, "vCBS", _money(totals.cbs))
    _text(cbs, "vCredPres", "0.00")
    _text(cbs, "vCredPresCondSus", "0.00")
    if document_total is not None:
        _text(total, "vNFTot", _money(_decimal(document_total) + totals.selective))

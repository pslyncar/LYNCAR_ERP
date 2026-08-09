from __future__ import annotations

from io import BytesIO

from brazilfiscalreport.danfe import Danfe
from lxml import etree
from reportlab.graphics import renderPDF
from reportlab.graphics.barcode import qr
from reportlab.graphics.shapes import Drawing
from reportlab.lib.units import mm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas
from pypdf import PdfReader, PdfWriter

from app.models.fiscal import CompanyFiscalSetting, FiscalDocument
from app.services.nfce_sp import NFE_NS, NfceValidationError


def _document_xml(document: FiscalDocument) -> etree._Element:
    source = document.xml_signed or document.xml_generated
    if not source:
        raise NfceValidationError("Documento fiscal sem XML para gerar o DANFE.")
    return etree.fromstring(source.encode("utf-8"))


def _protocol_node(document: FiscalDocument) -> etree._Element | None:
    if not document.xml_authorized:
        return None
    root = etree.fromstring(document.xml_authorized.encode("utf-8"))
    node = root.find(f".//{{{NFE_NS}}}protNFe")
    if node is None:
        return None
    return etree.fromstring(etree.tostring(node))


def build_processed_nfe_xml(document: FiscalDocument) -> bytes:
    nfe = _document_xml(document)
    protocol = _protocol_node(document)
    if protocol is None:
        raise NfceValidationError("NF-e autorizada sem protocolo XML da SEFAZ.")
    proc = etree.Element(
        f"{{{NFE_NS}}}nfeProc",
        versao="4.00",
        nsmap={None: NFE_NS},
    )
    proc.append(nfe)
    proc.append(protocol)
    return etree.tostring(
        proc,
        encoding="utf-8",
        xml_declaration=True,
    )


def generate_danfe_pdf(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
) -> bytes:
    if document.status not in {"authorized", "cancelled", "contingency_offline"}:
        raise NfceValidationError(
            "O DANFE so pode ser gerado para documento autorizado, cancelado ou em contingencia."
        )
    if document.document_type == "nfe":
        danfe = Danfe(xml=build_processed_nfe_xml(document))
        output = danfe.output()
        pdf = bytes(output or b"")
        return _stamp_cancelled(pdf) if document.status == "cancelled" else pdf
    return _generate_nfce_extract(setting, document)


def _stamp_cancelled(pdf_bytes: bytes) -> bytes:
    reader = PdfReader(BytesIO(pdf_bytes))
    writer = PdfWriter()
    for page in reader.pages:
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        overlay_buffer = BytesIO()
        overlay = canvas.Canvas(overlay_buffer, pagesize=(width, height))
        overlay.saveState()
        overlay.setFillAlpha(0.22)
        overlay.setFillColorRGB(0.8, 0, 0)
        overlay.setFont("Helvetica-Bold", 54)
        overlay.translate(width / 2, height / 2)
        overlay.rotate(45)
        overlay.drawCentredString(0, 0, "NF-e CANCELADA")
        overlay.restoreState()
        overlay.showPage()
        overlay.save()
        overlay_page = PdfReader(BytesIO(overlay_buffer.getvalue())).pages[0]
        page.merge_page(overlay_page)
        writer.add_page(page)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()


def _find_text(root: etree._Element, path: str, default: str = "") -> str:
    return root.findtext(path) or default


def _money_br(value: str) -> str:
    try:
        return f"{float(value):,.2f}".replace(",", "_").replace(".", ",").replace("_", ".")
    except (TypeError, ValueError):
        return value


def _draw_centered_wrapped(
    pdf: canvas.Canvas,
    text: str,
    y: float,
    *,
    width: float,
    font: str = "Helvetica",
    size: float = 7,
    leading: float = 9,
) -> float:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if stringWidth(candidate, font, size) <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    pdf.setFont(font, size)
    for line in lines:
        pdf.drawCentredString(40 * mm, y, line)
        y -= leading
    return y


def _generate_nfce_extract(
    setting: CompanyFiscalSetting,
    document: FiscalDocument,
) -> bytes:
    root = _document_xml(document)
    inf = root.find(f"{{{NFE_NS}}}infNFe")
    if inf is None:
        raise NfceValidationError("XML NFC-e sem infNFe.")
    items = root.findall(f".//{{{NFE_NS}}}det")
    height = max(135, 120 + len(items) * 12) * mm
    output = BytesIO()
    pdf = canvas.Canvas(output, pagesize=(80 * mm, height))
    y = height - 8 * mm
    center_width = 72 * mm

    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawCentredString(40 * mm, y, setting.trade_name or setting.legal_name or "")
    y -= 4 * mm
    pdf.setFont("Helvetica", 7)
    pdf.drawCentredString(40 * mm, y, f"CNPJ: {setting.cnpj or '-'}")
    y -= 3.5 * mm
    address = (
        f"{setting.address_line or ''}, {setting.address_number or ''} - "
        f"{setting.neighborhood or ''} - {setting.city or ''}/{setting.uf or ''}"
    )
    y = _draw_centered_wrapped(pdf, address, y, width=center_width)
    pdf.line(4 * mm, y, 76 * mm, y)
    y -= 4 * mm

    pdf.setFont("Helvetica-Bold", 8)
    pdf.drawCentredString(
        40 * mm,
        y,
        "DANFE NFC-e - Documento Auxiliar",
    )
    y -= 3.5 * mm
    pdf.setFont("Helvetica", 7)
    pdf.drawCentredString(
        40 * mm,
        y,
        "da Nota Fiscal de Consumidor Eletronica",
    )
    y -= 4 * mm
    if document.environment == "homologacao":
        pdf.setFont("Helvetica-Bold", 8)
        pdf.drawCentredString(
            40 * mm,
            y,
            "EMITIDA EM HOMOLOGACAO - SEM VALOR FISCAL",
        )
        y -= 4 * mm
    if document.status == "contingency_offline":
        pdf.setFont("Helvetica-Bold", 8)
        pdf.drawCentredString(
            40 * mm,
            y,
            "EMITIDA EM CONTINGENCIA OFFLINE",
        )
        y -= 4 * mm

    pdf.line(4 * mm, y, 76 * mm, y)
    y -= 4 * mm
    pdf.setFont("Helvetica-Bold", 6.5)
    pdf.drawString(4 * mm, y, "CODIGO  DESCRICAO")
    pdf.drawRightString(76 * mm, y, "QTD x UNIT. = TOTAL")
    y -= 3.5 * mm
    pdf.setFont("Helvetica", 6.2)
    for item in items:
        product = item.find(f"{{{NFE_NS}}}prod")
        if product is None:
            continue
        code = _find_text(product, f"{{{NFE_NS}}}cProd")
        description = _find_text(product, f"{{{NFE_NS}}}xProd")
        quantity = _find_text(product, f"{{{NFE_NS}}}qCom")
        unit_value = _find_text(product, f"{{{NFE_NS}}}vUnCom")
        total = _find_text(product, f"{{{NFE_NS}}}vProd")
        pdf.drawString(4 * mm, y, f"{code}  {description[:46]}")
        y -= 3 * mm
        pdf.drawRightString(
            76 * mm,
            y,
            f"{quantity} x {_money_br(unit_value)} = {_money_br(total)}",
        )
        y -= 4 * mm

    total_node = root.find(f".//{{{NFE_NS}}}ICMSTot")
    pdf.line(4 * mm, y, 76 * mm, y)
    y -= 4 * mm
    pdf.setFont("Helvetica-Bold", 8)
    pdf.drawString(4 * mm, y, f"Qtd. total de itens: {len(items)}")
    y -= 4 * mm
    total_value = (
        _find_text(total_node, f"{{{NFE_NS}}}vNF") if total_node is not None else "0"
    )
    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawString(4 * mm, y, "VALOR TOTAL R$")
    pdf.drawRightString(76 * mm, y, _money_br(total_value))
    y -= 5 * mm

    pdf.setFont("Helvetica", 7)
    for payment in root.findall(f".//{{{NFE_NS}}}detPag"):
        method = _find_text(payment, f"{{{NFE_NS}}}tPag")
        value = _find_text(payment, f"{{{NFE_NS}}}vPag")
        pdf.drawString(4 * mm, y, f"Pagamento {method}")
        pdf.drawRightString(76 * mm, y, _money_br(value))
        y -= 3.5 * mm
    change = _find_text(root, f".//{{{NFE_NS}}}pag/{{{NFE_NS}}}vTroco")
    if change:
        pdf.drawString(4 * mm, y, "Troco")
        pdf.drawRightString(76 * mm, y, _money_br(change))
        y -= 4 * mm

    pdf.line(4 * mm, y, 76 * mm, y)
    y -= 4 * mm
    pdf.setFont("Helvetica-Bold", 7)
    pdf.drawCentredString(40 * mm, y, "Consulte pela chave de acesso em")
    y -= 3.5 * mm
    consultation_url = _find_text(root, f".//{{{NFE_NS}}}urlChave")
    y = _draw_centered_wrapped(
        pdf,
        consultation_url,
        y,
        width=center_width,
        size=6.5,
        leading=7.5,
    )
    access_key = document.access_key or ""
    grouped_key = " ".join(
        access_key[index : index + 4] for index in range(0, len(access_key), 4)
    )
    y = _draw_centered_wrapped(
        pdf,
        f"CHAVE: {grouped_key}",
        y,
        width=center_width,
        size=6.5,
        leading=7.5,
    )
    pdf.setFont("Helvetica", 6.5)
    pdf.drawCentredString(
        40 * mm,
        y,
        f"Protocolo: {document.sefaz_protocol or '-'}",
    )
    y -= 4 * mm

    qr_value = _find_text(root, f".//{{{NFE_NS}}}qrCode")
    if qr_value:
        widget = qr.QrCodeWidget(qr_value)
        bounds = widget.getBounds()
        size = 32 * mm
        drawing = Drawing(
            size,
            size,
            transform=[
                size / (bounds[2] - bounds[0]),
                0,
                0,
                size / (bounds[3] - bounds[1]),
                0,
                0,
            ],
        )
        drawing.add(widget)
        renderPDF.draw(drawing, pdf, 24 * mm, max(8 * mm, y - size))
        y -= size + 3 * mm

    if document.status == "cancelled":
        pdf.saveState()
        pdf.setFillColorRGB(0.8, 0, 0)
        pdf.setFont("Helvetica-Bold", 18)
        pdf.translate(40 * mm, height / 2)
        pdf.rotate(45)
        pdf.drawCentredString(0, 0, "NFC-e CANCELADA")
        pdf.restoreState()

    pdf.showPage()
    pdf.save()
    return output.getvalue()

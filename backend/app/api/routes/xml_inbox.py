from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, require_any_permission
from app.core.config import get_settings
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.company import Company
from app.models.fiscal import CompanyFiscalSetting
from app.models.product import Product
from app.models.stock_entry import StockEntry, StockEntryItem
from app.services.stock_product_matching import resolve_product_match
from app.api.routes.stock_entries import _apply_product_purchase_conversion_to_entry_item
from app.models.supplier import Supplier
from app.models.user import User
from app.models.xml_inbox import XmlInboxMessage
from app.schemas.xml_inbox import (
    XmlInboxMessageRead,
    XmlInboxSettingsRead,
    XmlInboundPayload,
    XmlInboundResult,
)
from app.schemas.stock_entry import StockEntryRead
from app.services.nfe_xml import parse_nfe_xml
from app.services.tenancy import company_code_from_token_claims, session_for_company

router = APIRouter()


def _digits(value: str | None) -> str:
    return "".join(char for char in (value or "") if char.isdigit())


def _normalize_product_code(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = "".join(char for char in value.strip().upper() if char.isalnum())
    if not normalized or normalized == "SEMGTIN":
        return None
    return normalized


def _find_supplier_by_document(db: Session, document: str | None) -> Supplier | None:
    """Localiza fornecedor ignorando pontuação, barras, hífens e espaços."""
    normalized_document = _digits(document)
    if not normalized_document:
        return None
    supplier = db.scalar(
        select(Supplier).where(Supplier.document_number == normalized_document)
    )
    if supplier is not None:
        return supplier
    return next(
        (
            candidate
            for candidate in db.scalars(select(Supplier)).all()
            if _digits(candidate.document_number) == normalized_document
        ),
        None,
    )


def _find_product_by_code(db: Session, code: str | None) -> Product | None:
    normalized_code = _normalize_product_code(code)
    if normalized_code is None:
        return None
    product = db.scalar(
        select(Product).where(
            or_(
                Product.barcode == code,
                Product.internal_code == code,
                Product.purchase_package_barcode == code,
            )
        )
    )
    if product is not None:
        return product
    for candidate in db.scalars(select(Product)).all():
        if _normalize_product_code(candidate.barcode) == normalized_code:
            return candidate
        if _normalize_product_code(candidate.internal_code) == normalized_code:
            return candidate
        if _normalize_product_code(candidate.purchase_package_barcode) == normalized_code:
            return candidate
    return None


def _company_code(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> str:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Token de acesso ausente.")
    payload = decode_access_token(credentials.credentials)
    if payload.get("scope") == "master":
        raise HTTPException(status_code=403, detail="Caixa de XML disponivel apenas para empresas.")
    try:
        return company_code_from_token_claims(payload)
    except LookupError as exc:
        raise HTTPException(status_code=401, detail="Contexto da empresa invalido.") from exc


def _email_address(company: Company) -> str:
    settings = get_settings()
    return f"xml+{company.code}-{company.xml_email_token}@{settings.xml_inbound_domain}"


@router.get("/settings", response_model=XmlInboxSettingsRead)
def get_xml_inbox_settings(
    company_code: str = Depends(_company_code),
    _: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> XmlInboxSettingsRead:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None or not company.xml_email_token:
            raise HTTPException(status_code=404, detail="Endereco de XML nao configurado.")
        return XmlInboxSettingsRead(
            email_address=_email_address(company),
            enabled=company.xml_email_enabled,
        )


@router.get("/messages", response_model=list[XmlInboxMessageRead])
def list_xml_inbox_messages(
    limit: int = 50,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> list[XmlInboxMessage]:
    messages = list(
        db.scalars(
            select(XmlInboxMessage)
            .order_by(XmlInboxMessage.received_at.desc(), XmlInboxMessage.id.desc())
            .limit(min(max(limit, 1), 200))
        ).all()
    )
    # Um XML de fornecedor ainda não cadastrado permanece guardado. Assim que
    # o cadastro com o mesmo CNPJ existir, ele é liberado sem reenviar o XML.
    released = False
    for message in messages:
        if message.status != "pending_supplier" or not message.supplier_document:
            continue
        supplier = _find_supplier_by_document(db, message.supplier_document)
        if supplier is not None:
            message.status = "pending_receipt"
            message.supplier_name = supplier.name
            message.rejection_reason = None
            released = True
    if released:
        db.commit()
    return messages


def _create_stock_entry_from_parsed_xml(
    db: Session,
    parsed: dict,
    *,
    source: str = "email_xml",
    notes: str = "Gerada a partir da Caixa de XML. Aguardando conferência.",
) -> StockEntry:
    invoice_key = str(parsed.get("invoice_key") or "").strip() or None
    if invoice_key:
        duplicate = db.scalar(select(StockEntry).where(StockEntry.invoice_key == invoice_key))
        if duplicate is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Esta chave NF-e ja possui uma entrada de recebimento.",
            )
    supplier_document = _digits(parsed.get("supplier_document")) or None
    supplier = _find_supplier_by_document(db, supplier_document)
    entry = StockEntry(
        supplier_id=supplier.id if supplier else None,
        user_id=None,
        source=source,
        status="receiving",
        invoice_key=invoice_key,
        invoice_number=parsed.get("invoice_number"),
        invoice_series=parsed.get("invoice_series"),
        supplier_name=supplier.name if supplier else parsed.get("supplier_name"),
        supplier_document=supplier.document_number if supplier else supplier_document,
        notes=notes,
    )
    db.add(entry)
    db.flush()
    for item in parsed["items"]:
        barcode = str(item.get("barcode") or "").strip() or None
        tax_gtin = str(item.get("tax_gtin") or "").strip() or None
        match = resolve_product_match(
            db,
            supplier_id=supplier.id if supplier else None,
            supplier_product_code=str(item.get("supplier_product_code") or "") or None,
            commercial_gtin=barcode,
            tax_gtin=tax_gtin,
            internal_code=None,
            description=str(item.get("description") or ""),
        )
        # Correspondências determinísticas por vínculo do fornecedor ou GTIN
        # podem ser aplicadas automaticamente. Descrição nunca associa sozinha.
        product = match.product if match.status == "matched" else None
        expiration_date = item.get("expiration_date")
        if isinstance(expiration_date, str) and expiration_date:
            expiration_date = date.fromisoformat(expiration_date)
        entry.items.append(
            StockEntryItem(
                product_id=product.id if product else None,
                description=str(item["description"]),
                barcode=barcode,
                tax_gtin=tax_gtin,
                supplier_product_code=item.get("supplier_product_code"),
                invoice_quantity=item["quantity"],
                invoice_unit=str(item["unit"]),
                tax_quantity=item.get("tax_quantity"),
                tax_unit=item.get("tax_unit"),
                quantity=item["quantity"],
                received_quantity=Decimal("0"),
                unit=str(item["unit"]),
                unit_cost=item["unit_cost"],
                total_cost=item["total_cost"],
                ncm=item.get("ncm"),
                cfop=item.get("cfop"),
                origin=item.get("origin"),
                cst=item.get("cst"),
                csosn=item.get("csosn"),
                icms_rate=item.get("icms_rate"),
                pis_rate=item.get("pis_rate"),
                cofins_rate=item.get("cofins_rate"),
                ipi_rate=item.get("ipi_rate"),
                ibs_cbs_cst=item.get("ibs_cbs_cst"),
                ibs_cbs_classification=item.get("ibs_cbs_classification"),
                cbs_rate=item.get("cbs_rate"),
                ibs_state_rate=item.get("ibs_state_rate"),
                ibs_city_rate=item.get("ibs_city_rate"),
                selective_tax_cst=item.get("selective_tax_cst"),
                selective_tax_classification=item.get("selective_tax_classification"),
                selective_tax_rate=item.get("selective_tax_rate"),
                batch_number=item.get("batch_number"),
                expiration_date=expiration_date,
                check_status="accepted" if product else "pending_product",
                check_notes=(
                    "Produto associado automaticamente por código/GTIN."
                    if match.product is not None
                    else "Produto aguardando associação pelo operador."
                ),
            )
        )
        if product is not None:
            _apply_product_purchase_conversion_to_entry_item(entry.items[-1], product)
    return entry


@router.post(
    "/inbound/{routing_token}",
    response_model=XmlInboundResult,
    status_code=status.HTTP_200_OK,
)
def receive_xml_email(
    routing_token: str,
    payload: XmlInboundPayload,
    x_inbound_secret: str | None = Header(default=None),
) -> XmlInboundResult:
    settings = get_settings()
    if (
        settings.app_env.lower() == "production"
        and settings.xml_inbound_secret == "change-me-xml-inbound"
    ):
        raise HTTPException(
            status_code=503,
            detail="Recebimento de XML desativado ate configurar XML_INBOUND_SECRET.",
        )
    if not x_inbound_secret or x_inbound_secret != settings.xml_inbound_secret:
        raise HTTPException(status_code=401, detail="Assinatura do provedor de e-mail invalida.")
    if len(payload.xml_content.encode("utf-8")) > settings.xml_inbound_max_bytes:
        raise HTTPException(status_code=413, detail="XML excede o tamanho permitido.")

    with MasterSessionLocal() as master_db:
        company = master_db.scalar(
            select(Company).where(
                Company.xml_email_token == routing_token,
                Company.xml_email_enabled.is_(True),
                Company.active.is_(True),
            )
        )
        if company is None:
            raise HTTPException(status_code=404, detail="Endereco de XML inexistente ou desativado.")
        company_code = company.code

    try:
        parsed = parse_nfe_xml(payload.xml_content)
    except ValueError as exc:
        with session_for_company(company_code) as db:
            db.add(
                XmlInboxMessage(
                    status="invalid_xml",
                    sender_email=payload.sender_email,
                    subject=payload.subject,
                    attachment_name=payload.attachment_name,
                    rejection_reason=str(exc),
                )
            )
            db.commit()
        return XmlInboundResult(
            accepted=False,
            status="invalid_xml",
            message="Anexo rejeitado: XML de NF-e invalido.",
        )

    with session_for_company(company_code) as db:
        fiscal = db.scalar(
            select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc())
        )
        expected_cnpj = _digits(fiscal.cnpj if fiscal is not None else None)
        recipient_document = _digits(parsed.get("recipient_document"))
        base_message = dict(
            sender_email=payload.sender_email,
            subject=payload.subject,
            attachment_name=payload.attachment_name,
            supplier_name=parsed.get("supplier_name"),
            supplier_document=_digits(parsed.get("supplier_document")) or None,
            recipient_document=recipient_document or None,
            invoice_key=parsed.get("invoice_key"),
            invoice_number=parsed.get("invoice_number"),
        )

        if len(expected_cnpj) != 14:
            db.add(
                XmlInboxMessage(
                    **base_message,
                    status="company_cnpj_missing",
                    rejection_reason="Empresa sem CNPJ fiscal configurado.",
                )
            )
            db.commit()
            return XmlInboundResult(
                accepted=False,
                status="company_cnpj_missing",
                message="XML rejeitado: configure o CNPJ fiscal da empresa.",
            )

        if recipient_document != expected_cnpj:
            db.add(
                XmlInboxMessage(
                    **base_message,
                    status="cnpj_mismatch",
                    rejection_reason="CNPJ destinatario do XML nao pertence a esta empresa.",
                )
            )
            db.commit()
            return XmlInboundResult(
                accepted=False,
                status="cnpj_mismatch",
                message="XML rejeitado: CNPJ destinatario diferente da empresa.",
            )

        supplier_document = _digits(parsed.get("supplier_document")) or None
        supplier = _find_supplier_by_document(db, supplier_document)
        if supplier is None:
            db.add(
                XmlInboxMessage(
                    **base_message,
                    status="pending_supplier",
                    rejection_reason="Fornecedor do XML ainda nao esta cadastrado para este CNPJ.",
                )
            )
            db.commit()
            return XmlInboundResult(
                accepted=True,
                status="pending_supplier",
                message="XML recebido. Cadastre o fornecedor pelo CNPJ para liberar a importacao.",
            )

        invoice_key = str(parsed.get("invoice_key") or "").strip() or None
        if invoice_key:
            duplicate = db.scalar(
                select(StockEntry).where(StockEntry.invoice_key == invoice_key)
            )
            if duplicate is not None:
                db.add(
                    XmlInboxMessage(
                        **base_message,
                        status="duplicate",
                        stock_entry_id=duplicate.id,
                        rejection_reason="Chave NF-e ja importada.",
                    )
                )
                db.commit()
                return XmlInboundResult(
                    accepted=False,
                    status="duplicate",
                    message="XML ignorado: esta chave NF-e ja foi importada.",
                    stock_entry_id=duplicate.id,
                )
            pending_inbox = db.scalar(
                select(XmlInboxMessage).where(
                    XmlInboxMessage.invoice_key == invoice_key,
                    XmlInboxMessage.status.in_(
                        ["pending_receipt", "pending_supplier", "imported"]
                    ),
                )
            )
            if pending_inbox is not None:
                return XmlInboundResult(
                    accepted=False,
                    status="duplicate",
                    message="XML ignorado: esta chave NF-e ja esta na Caixa de XML.",
                    stock_entry_id=pending_inbox.stock_entry_id,
                )

        inbox = XmlInboxMessage(
            **base_message,
            status="pending_receipt",
            xml_content=payload.xml_content,
        )
        db.add(inbox)
        db.commit()
        return XmlInboundResult(
            accepted=True,
            status="pending_receipt",
            message="XML importado para a Caixa de XML. Aguarde a decisao do usuario para gerar recebimento.",
        )
        if product is not None:
            _apply_product_purchase_conversion_to_entry_item(entry.items[-1], product)


@router.post(
    "/messages/upload",
    response_model=XmlInboundResult,
    status_code=status.HTTP_201_CREATED,
)
def upload_xml_file(
    payload: XmlInboundPayload,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("stock:entries:create")),
) -> XmlInboundResult:
    """Recebe XML escolhido pelo usuário com as mesmas travas fiscais do e-mail."""
    settings = get_settings()
    if len(payload.xml_content.encode("utf-8")) > settings.xml_inbound_max_bytes:
        raise HTTPException(status_code=413, detail="XML excede o tamanho permitido.")
    try:
        parsed = parse_nfe_xml(payload.xml_content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    fiscal = db.scalar(
        select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc())
    )
    expected_cnpj = _digits(fiscal.cnpj if fiscal is not None else None)
    recipient_document = _digits(parsed.get("recipient_document"))
    if len(expected_cnpj) != 14:
        raise HTTPException(
            status_code=400,
            detail="Empresa sem CNPJ fiscal configurado.",
        )
    if recipient_document != expected_cnpj:
        raise HTTPException(
            status_code=400,
            detail="O CNPJ destinatario do XML nao pertence a esta empresa.",
        )

    supplier_document = _digits(parsed.get("supplier_document")) or None
    supplier = _find_supplier_by_document(db, supplier_document)
    if supplier is None:
        db.add(
            XmlInboxMessage(
                status="pending_supplier",
                sender_email=None,
                subject=payload.subject or "XML importado manualmente",
                attachment_name=payload.attachment_name,
                supplier_name=parsed.get("supplier_name"),
                supplier_document=supplier_document,
                recipient_document=recipient_document,
                invoice_key=str(parsed.get("invoice_key") or "").strip() or None,
                invoice_number=parsed.get("invoice_number"),
                rejection_reason="Fornecedor do XML ainda nao esta cadastrado para este CNPJ.",
                xml_content=payload.xml_content,
            )
        )
        db.commit()
        return XmlInboundResult(
            accepted=True,
            status="pending_supplier",
            message="XML recebido. Cadastre o fornecedor pelo CNPJ para liberar a importacao.",
        )

    invoice_key = str(parsed.get("invoice_key") or "").strip() or None
    if not invoice_key:
        raise HTTPException(status_code=400, detail="XML sem chave de acesso da NF-e.")
    duplicate_entry = db.scalar(
        select(StockEntry).where(StockEntry.invoice_key == invoice_key)
    )
    if duplicate_entry is not None:
        raise HTTPException(
            status_code=409,
            detail="Esta chave NF-e ja possui uma entrada de recebimento.",
        )
    duplicate_message = db.scalar(
        select(XmlInboxMessage).where(
            XmlInboxMessage.invoice_key == invoice_key,
            XmlInboxMessage.status.in_(
                ["pending_receipt", "pending_supplier", "imported"]
            ),
        )
    )
    if duplicate_message is not None:
        raise HTTPException(
            status_code=409,
            detail="Esta chave NF-e ja esta aguardando importacao na Caixa de XML.",
        )

    db.add(
        XmlInboxMessage(
            status="pending_receipt",
            sender_email=None,
            subject=payload.subject or "XML importado manualmente",
            attachment_name=payload.attachment_name,
            supplier_name=supplier.name,
            supplier_document=supplier.document_number,
            recipient_document=recipient_document,
            invoice_key=invoice_key,
            invoice_number=parsed.get("invoice_number"),
            xml_content=payload.xml_content,
        )
    )
    db.commit()
    return XmlInboundResult(
        accepted=True,
        status="pending_receipt",
        message="XML validado e aguardando importacao para recebimento.",
    )


@router.post(
    "/messages/{message_id}/receipt",
    response_model=StockEntryRead,
    status_code=status.HTTP_201_CREATED,
)
def create_receipt_from_xml_message(
    message_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("stock:entries:create")),
) -> StockEntry:
    message = db.get(XmlInboxMessage, message_id)
    if message is None:
        raise HTTPException(status_code=404, detail="XML nao encontrado.")
    if message.stock_entry_id is not None:
        entry = db.get(StockEntry, message.stock_entry_id)
        if entry is None:
            raise HTTPException(status_code=404, detail="Entrada vinculada nao encontrada.")
        return entry
    if message.status != "pending_receipt":
        if message.status == "pending_supplier":
            raise HTTPException(
                status_code=409,
                detail="Cadastre o fornecedor com o CNPJ do XML para liberar esta importacao.",
            )
        raise HTTPException(
            status_code=409,
            detail="Este XML nao esta pendente para gerar recebimento.",
        )
    if not message.xml_content:
        raise HTTPException(status_code=400, detail="XML sem conteudo armazenado.")
    try:
        parsed = parse_nfe_xml(message.xml_content)
    except ValueError as exc:
        message.status = "invalid_xml"
        message.rejection_reason = str(exc)
        db.commit()
        raise HTTPException(status_code=400, detail="XML da NF-e invalido.") from exc

    entry = _create_stock_entry_from_parsed_xml(db, parsed)
    message.status = "imported"
    message.stock_entry_id = entry.id
    db.commit()
    db.refresh(entry)
    return entry

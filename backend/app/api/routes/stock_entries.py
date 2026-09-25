from datetime import datetime, timezone
from decimal import Decimal
from difflib import SequenceMatcher
import json
import urllib.error
import urllib.request

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.product import Product
from app.models.fiscal import CompanyFiscalSetting, FiscalDocument, FiscalDocumentItem
from app.models.stock_entry import StockEntry, StockEntryItem, StockEntryItemLot
from app.models.stock_entry_audit import StockEntryAuditEvent
from app.models.stock_movement import StockMovement
from app.models.supplier import Supplier
from app.models import product_barcode as _product_barcode_model  # noqa: F401
from app.models import supplier_product_link as _supplier_product_link_model  # noqa: F401
from app.models.supplier_product_link import SupplierProductLink
from app.models.receiving_scan import ReceivingScan
from app.models.receiving_session import ReceivingSession
from app.models.user import User
from app.schemas.stock_entry import (
    NfeKeyDownloadRequest,
    NfeXmlImportRequest,
    NfeXmlPreview,
    NfeXmlPreviewItem,
    StockEntryCreate,
    StockEntryItemCreate,
    StockEntryMobileReceiveItem,
    StockEntryItemMatchRequest,
    StockEntryRead,
    StockReceiptPage,
    StockReceiptSummary,
    ReceivingScanCreate,
    ReceivingSessionCreate,
    ReceivingSessionRead,
    StockEntryReversalRequest,
    StockEntryProductSuggestion,
    StockEntryItemLotCreate,
    StockEntryItemLotRead,
    StockDevolutionDraftRead,
)
from app.schemas.stock_entry_audit import StockEntryAuditEventRead
from app.schemas.supplier import SupplierCreate, SupplierRead, SupplierUpdate
from app.services.access_control import user_has_permission
from app.services.nfe_xml import parse_nfe_xml
from app.services.product_batches import return_to_batch, upsert_product_batch
from app.services.product_costs import apply_stock_in, apply_stock_out
from app.services.fiscal_assistant import learn_from_stock_entry_item
from app.services.fiscal_stock import refresh_many_product_fiscal_balances
from app.services.stock_product_matching import resolve_product_match, normalize_product_code

router = APIRouter()


def _audit_entry(
    db: Session,
    entry: StockEntry,
    user: User | None,
    action: str,
    *,
    item: StockEntryItem | None = None,
    source: str = "web",
    reason: str | None = None,
    old_value: str | None = None,
    new_value: str | None = None,
) -> None:
    db.add(
        StockEntryAuditEvent(
            stock_entry_id=entry.id,
            stock_entry_item_id=item.id if item is not None else None,
            user_id=user.id if user is not None else None,
            action=action,
            source=source,
            reason=reason,
            old_value=old_value,
            new_value=new_value,
        )
    )


def _only_digits(value: str | None) -> str | None:
    if value is None:
        return None
    digits = "".join(char for char in value if char.isdigit())
    return digits or None


def _normalize_product_code(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = "".join(char for char in value.strip().upper() if char.isalnum())
    if not normalized or normalized == "SEMGTIN":
        return None
    return normalized


def _find_product_by_code(db: Session, code: str | None) -> Product | None:
    normalized_code = _normalize_product_code(code)
    if normalized_code is None:
        return None
    product = db.scalar(
        select(Product).where(
            (Product.barcode == code)
            | (Product.internal_code == code)
            | (Product.purchase_package_barcode == code)
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


def _normalize_mobile_received_quantity(
    product: Product,
    barcode: str | None,
    quantity: Decimal,
    unit: str,
    unit_cost: Decimal,
) -> tuple[Decimal, str, Decimal]:
    factor = product.purchase_package_factor or Decimal("0")
    if not product.purchase_conversion_enabled or factor <= 0:
        return quantity, unit, unit_cost
    package_unit = (product.purchase_invoice_unit or "").strip().lower()
    received_unit = (unit or "").strip().lower()
    package_barcode = _normalize_product_code(product.purchase_package_barcode)
    scanned_barcode = _normalize_product_code(barcode)
    is_package_scan = package_barcode is not None and package_barcode == scanned_barcode
    is_package_unit = bool(package_unit) and received_unit == package_unit
    is_stock_unit = received_unit == (product.unit or "").strip().lower()
    if is_stock_unit or not (is_package_scan or is_package_unit):
        return quantity, unit, unit_cost
    converted_quantity = quantity * factor
    converted_unit_cost = unit_cost / factor if factor > 0 else unit_cost
    return converted_quantity, product.unit or unit, converted_unit_cost


def _apply_product_purchase_conversion_to_entry_item(item: StockEntryItem, product: Product) -> bool:
    factor = product.purchase_package_factor or Decimal("0")
    if not product.purchase_conversion_enabled or factor <= 0:
        return False
    if item.package_conversion_factor is not None and item.package_conversion_factor > 0:
        return False
    package_unit = (product.purchase_invoice_unit or "").strip().lower()
    item_unit = (item.unit or "").strip().lower()
    package_barcode = _normalize_product_code(product.purchase_package_barcode)
    item_barcode = _normalize_product_code(item.barcode)
    is_package_barcode = package_barcode is not None and package_barcode == item_barcode
    is_package_unit = bool(package_unit) and item_unit == package_unit
    is_stock_unit = item_unit == (product.unit or "").strip().lower()
    if not is_package_barcode and (is_stock_unit or not is_package_unit):
        return False
    original_quantity = item.invoice_quantity or item.quantity
    converted_quantity = original_quantity * factor
    if converted_quantity <= 0:
        return False
    item.invoice_quantity = original_quantity
    item.invoice_unit = item.invoice_unit or product.purchase_invoice_unit or item.unit
    item.package_conversion_factor = factor
    item.quantity = converted_quantity
    if (
        item.received_quantity is not None
        and item.received_quantity > 0
        and item.received_quantity <= original_quantity
    ):
        item.received_quantity = item.received_quantity * factor
    item.unit = product.unit or item.unit
    item.unit_cost = item.total_cost / converted_quantity if item.total_cost else item.unit_cost / factor
    return True


def _apply_explicit_conversion_to_entry_item(
    item: StockEntryItem,
    *,
    factor: Decimal,
    stock_unit: str,
) -> bool:
    """Converts the supplier's commercial quantity into the product stock unit.

    The invoice values remain stored separately. Only the operational quantity
    used for conference, batches and stock movement is converted.
    """
    if factor <= 0 or not stock_unit.strip() or item.package_conversion_factor:
        return False
    original_quantity = item.invoice_quantity or item.quantity
    converted_quantity = original_quantity * factor
    if converted_quantity <= 0:
        return False
    item.invoice_quantity = original_quantity
    item.invoice_unit = item.invoice_unit or item.unit
    item.package_conversion_factor = factor
    item.quantity = converted_quantity
    if item.received_quantity is not None and item.received_quantity > 0:
        item.received_quantity = item.received_quantity * factor
    item.unit = stock_unit.strip().lower()
    item.unit_cost = item.total_cost / converted_quantity if item.total_cost else item.unit_cost / factor
    return True


def _apply_entry_tax_to_product(product: Product, item: StockEntryItem | StockEntryItemCreate | StockEntryMobileReceiveItem) -> bool:
    """Atualiza o cadastro do produto com dados seguros da NF-e de entrada.

    O XML de compra descreve a operacao do fornecedor. Ele pode alimentar
    cadastro, custo e historico fiscal da entrada, mas nao deve virar
    automaticamente regra fiscal de saida. CFOP/CST/CSOSN/alíquotas/IBS-CBS
    continuam preservados no item da entrada e no Assistente Fiscal, para
    consulta e sugestao, sem sobrescrever a tributacao usada para NFC-e/NF-e.
    """
    changed = False
    if getattr(item, "ncm", None) and not product.ncm:
        product.ncm = item.ncm
        changed = True
    if getattr(item, "origin", None) and not product.origin:
        product.origin = item.origin
        changed = True
    return changed


def _relink_pending_entry_items(db: Session, entry: StockEntry) -> bool:
    changed = False
    for item in entry.items:
        product = db.get(Product, item.product_id) if item.product_id is not None else None
        if product is None:
            product = _find_product_by_code(db, item.barcode)
        if product is None:
            continue
        if item.product_id is None:
            item.product_id = product.id
            item.description = product.name or item.description
            item.barcode = item.barcode or product.barcode or product.internal_code
            if item.check_status == "pending_product":
                item.check_status = "accepted"
            changed = True
        if _apply_entry_tax_to_product(product, item):
            changed = True
        if _apply_product_purchase_conversion_to_entry_item(item, product):
            changed = True
    return changed


def _entry_or_404(db: Session, entry_id: int) -> StockEntry:
    entry = db.scalar(
        select(StockEntry)
        .options(selectinload(StockEntry.items).selectinload(StockEntryItem.lots))
        .where(StockEntry.id == entry_id)
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Entrada de estoque nao encontrada.")
    return entry


def _calculate_entry_item_total(item: StockEntryItem) -> Decimal:
    return (item.received_quantity or Decimal("0")) * item.unit_cost


def _validate_receiving_traceability(item: StockEntryItem, product: Product) -> None:
    """Valida regras fiscais explícitas, sem travar a entrada por lote ausente."""
    lots = list(item.lots or [])
    if product.requires_manufacturing_date and not (item.manufacturing_date or any(lot.manufacturing_date for lot in lots)):
        raise HTTPException(status_code=400, detail=f"Informe a data de fabricação de '{product.name}'.")
    if product.requires_expiration_date and not (item.expiration_date or any(lot.expiration_date for lot in lots)):
        raise HTTPException(status_code=400, detail=f"Informe a validade de '{product.name}'.")
    if product.requires_temperature and item.temperature_celsius is None and not any(lot.temperature_celsius is not None for lot in lots):
        raise HTTPException(status_code=400, detail=f"Informe a temperatura de recebimento de '{product.name}'.")
    minimum_days = product.minimum_shelf_life_days
    if minimum_days is not None:
        today = datetime.now(timezone.utc).date()
        expirations = [item.expiration_date, *(lot.expiration_date for lot in lots)]
        if any(expiration is not None and (expiration - today).days < minimum_days for expiration in expirations):
            raise HTTPException(
                status_code=400,
                detail=f"A validade de '{product.name}' está abaixo do mínimo configurado ({minimum_days} dias).",
            )


def _confirm_stock_entry(db: Session, entry: StockEntry, current_user: User) -> None:
    if entry.status == "confirmed":
        return
    total_amount = Decimal("0")
    accepted_product_ids: set[int] = set()
    for item in entry.items:
        check_status = item.check_status or "accepted"
        if check_status == "return" and not user_has_permission(db, current_user, "stock:entries:return"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem permissao para marcar devolucao de mercadoria.",
            )
        received_quantity = item.received_quantity or Decimal("0")
        product = db.get(Product, item.product_id) if item.product_id is not None else None
        if check_status == "accepted" and received_quantity <= 0:
            continue
        if received_quantity > 0 and product is None:
            raise HTTPException(
                status_code=400,
                detail=f"Item '{item.description}' precisa estar vinculado a um produto antes de confirmar.",
            )
        if check_status == "accepted" and product is not None:
            _validate_receiving_traceability(item, product)
            accepted_product_ids.add(product.id)
            _apply_entry_tax_to_product(product, item)
            learn_from_stock_entry_item(db, item, entry=entry, source=entry.source or "stock_entry")
            accepted_total = _calculate_entry_item_total(item)
            quantity_before = product.stock_quantity
            unit_cost, effective_total = apply_stock_in(product, received_quantity, accepted_total)
            product.purchase_total_cost = effective_total or accepted_total
            product.purchase_quantity = received_quantity
            total_amount += effective_total or accepted_total
            lots = list(item.lots or [])
            if lots:
                lot_total = sum((lot.quantity for lot in lots), Decimal("0"))
                if lot_total != received_quantity:
                    raise HTTPException(
                        status_code=400,
                        detail=f"A soma dos lotes de '{item.description}' ({lot_total}) deve ser igual ao conferido ({received_quantity}).",
                    )
                for lot in lots:
                    upsert_product_batch(
                        db, product, lot.quantity,
                        batch_number=lot.lot_number,
                        expiration_date=lot.expiration_date,
                        source_type="stock_entry", source_id=entry.id,
                        source_number=entry.invoice_number, supplier_name=entry.supplier_name,
                        invoice_number=entry.invoice_number, invoice_series=entry.invoice_series,
                        notes=lot.notes or item.check_notes,
                    )
            else:
                upsert_product_batch(
                    db, product, received_quantity,
                    batch_number=item.batch_number, expiration_date=item.expiration_date,
                    source_type="stock_entry", source_id=entry.id,
                    source_number=entry.invoice_number, supplier_name=entry.supplier_name,
                    invoice_number=entry.invoice_number, invoice_series=entry.invoice_series,
                    notes=item.check_notes,
                )
            db.add(
                StockMovement(
                    product_id=product.id,
                    user_id=current_user.id,
                    movement_type="purchase_in",
                    source_type="stock_entry",
                    source_id=entry.id,
                    source_number=entry.invoice_number,
                    quantity_delta=received_quantity,
                    quantity_before=quantity_before,
                    quantity_after=product.stock_quantity,
                    unit=product.unit,
                    unit_price=unit_cost,
                    total_value=effective_total or accepted_total,
                    reason="Entrada de mercadoria",
                    notes=f"Entrada de estoque #{entry.id}.",
                )
            )
    entry.total_amount = total_amount
    entry.status = "confirmed"
    entry.confirmed_at = datetime.now(timezone.utc)
    refresh_many_product_fiscal_balances(db, accepted_product_ids)


def _resolve_supplier(db: Session, entry_in: StockEntryCreate) -> tuple[Supplier | None, str | None]:
    supplier = db.get(Supplier, entry_in.supplier_id) if entry_in.supplier_id is not None else None
    if entry_in.supplier_id is not None and supplier is None:
        raise HTTPException(status_code=404, detail="Fornecedor nao encontrado.")
    supplier_document = _only_digits(entry_in.supplier_document)
    if supplier is None and supplier_document is not None:
        supplier = db.scalar(select(Supplier).where(Supplier.document_number == supplier_document))
    return supplier, supplier_document


def _append_stock_entry_item(entry: StockEntry, item_in: StockEntryItemCreate) -> None:
    check_status = item_in.check_status or "accepted"
    received_quantity = item_in.received_quantity
    if received_quantity is None:
        received_quantity = item_in.quantity if check_status == "accepted" else Decimal("0")
    total_cost = item_in.total_cost or (item_in.quantity * item_in.unit_cost)
    entry.items.append(
        StockEntryItem(
            product_id=item_in.product_id,
            description=item_in.description,
            barcode=item_in.barcode,
            tax_gtin=item_in.tax_gtin,
            supplier_product_code=normalize_product_code(item_in.supplier_product_code),
            invoice_quantity=item_in.invoice_quantity,
            invoice_unit=item_in.invoice_unit,
            tax_quantity=item_in.tax_quantity,
            tax_unit=item_in.tax_unit,
            package_conversion_factor=item_in.package_conversion_factor,
            quantity=item_in.quantity,
            received_quantity=received_quantity,
            unit=item_in.unit,
            unit_cost=item_in.unit_cost,
            total_cost=total_cost,
            ncm=item_in.ncm,
            cfop=item_in.cfop,
            origin=item_in.origin,
            cst=item_in.cst,
            csosn=item_in.csosn,
            icms_rate=item_in.icms_rate,
            pis_rate=item_in.pis_rate,
            cofins_rate=item_in.cofins_rate,
            ipi_rate=item_in.ipi_rate,
            ibs_cbs_cst=item_in.ibs_cbs_cst,
            ibs_cbs_classification=item_in.ibs_cbs_classification,
            cbs_rate=item_in.cbs_rate,
            ibs_state_rate=item_in.ibs_state_rate,
            ibs_city_rate=item_in.ibs_city_rate,
            selective_tax_cst=item_in.selective_tax_cst,
            selective_tax_classification=item_in.selective_tax_classification,
            selective_tax_rate=item_in.selective_tax_rate,
            batch_number=item_in.batch_number,
            expiration_date=item_in.expiration_date,
            manufacturing_date=item_in.manufacturing_date,
            temperature_celsius=item_in.temperature_celsius,
            discrepancy_reason=item_in.discrepancy_reason,
            storage_location=item_in.storage_location,
            check_status=check_status,
            check_notes=item_in.check_notes,
        )
    )


def _create_entry_record(
    db: Session,
    entry_in: StockEntryCreate,
    current_user: User,
    *,
    status_value: str,
) -> StockEntry:
    supplier, supplier_document = _resolve_supplier(db, entry_in)
    entry = StockEntry(
        supplier_id=supplier.id if supplier else None,
        user_id=current_user.id,
        source=entry_in.source,
        status=status_value,
        invoice_key=entry_in.invoice_key,
        invoice_number=entry_in.invoice_number,
        invoice_series=entry_in.invoice_series,
        supplier_name=supplier.name if supplier else entry_in.supplier_name,
        supplier_document=supplier.document_number if supplier else supplier_document,
        notes=entry_in.notes,
    )
    db.add(entry)
    db.flush()
    for item_in in entry_in.items:
        if item_in.product_id is not None and db.get(Product, item_in.product_id) is None:
            raise HTTPException(status_code=404, detail=f"Produto #{item_in.product_id} nao encontrado.")
        _append_stock_entry_item(entry, item_in)
    return entry


@router.get("/suppliers", response_model=list[SupplierRead])
def list_suppliers(
    active: bool | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("suppliers:view", "stock:view", "stock:entries:view", "stock:entries:create")),
) -> list[Supplier]:
    query = select(Supplier).order_by(Supplier.name)
    if active is not None:
        query = query.where(Supplier.active == active)
    return list(db.scalars(query).all())


@router.get("/cep/{cep}")
def lookup_cep(
    cep: str,
    current_user: User = Depends(
        require_any_permission(
            "suppliers:view",
            "suppliers:create",
            "suppliers:update",
            "stock:entries:view",
            "stock:entries:create",
        )
    ),
) -> dict:
    """Resolve a CEP server-side so the browser is not blocked by CORS."""
    del current_user
    digits = _only_digits(cep)
    if digits is None or len(digits) != 8:
        raise HTTPException(status_code=400, detail="Informe um CEP com 8 dígitos.")
    request = urllib.request.Request(
        f"https://viacep.com.br/ws/{digits}/json/",
        headers={"Accept": "application/json", "User-Agent": "Lyncar-ERP/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=502, detail="Não foi possível consultar o CEP agora.") from exc
    if not isinstance(data, dict) or data.get("erro") is True:
        return {"found": False}
    return {"found": True, **data}


@router.get("/suppliers/by-document/{document_number}", response_model=SupplierRead)
def get_supplier_by_document(
    document_number: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("suppliers:view", "stock:entries:create")),
) -> Supplier:
    document_digits = _only_digits(document_number)
    if not document_digits:
        raise HTTPException(status_code=400, detail="Documento invalido.")
    supplier = db.scalar(select(Supplier).where(Supplier.document_number == document_digits))
    if supplier is None:
        raise HTTPException(status_code=404, detail="Fornecedor nao encontrado.")
    return supplier


@router.post("/suppliers", response_model=SupplierRead, status_code=status.HTTP_201_CREATED)
def create_supplier(
    supplier_in: SupplierCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("suppliers:create", "stock:entries:create")),
) -> Supplier:
    data = supplier_in.model_dump()
    data["document_number"] = _only_digits(data.get("document_number"))
    if data["document_number"] is not None:
        existing = db.scalar(select(Supplier).where(Supplier.document_number == data["document_number"]))
        if existing is not None:
            raise HTTPException(status_code=409, detail="Fornecedor ja cadastrado com este documento.")
    supplier = Supplier(**data)
    db.add(supplier)
    db.commit()
    db.refresh(supplier)
    return supplier


@router.put("/suppliers/{supplier_id}", response_model=SupplierRead)
def update_supplier(
    supplier_id: int,
    supplier_in: SupplierUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("suppliers:update")),
) -> Supplier:
    supplier = db.get(Supplier, supplier_id)
    if supplier is None:
        raise HTTPException(status_code=404, detail="Fornecedor nao encontrado.")
    data = supplier_in.model_dump(exclude_unset=True)
    if "document_number" in data:
        data["document_number"] = _only_digits(data.get("document_number"))
        if data["document_number"] is not None:
            existing = db.scalar(
                select(Supplier).where(
                    Supplier.document_number == data["document_number"],
                    Supplier.id != supplier.id,
                )
            )
            if existing is not None:
                raise HTTPException(status_code=409, detail="Outro fornecedor ja usa este documento.")
    for field, value in data.items():
        setattr(supplier, field, value)
    db.commit()
    db.refresh(supplier)
    return supplier


@router.delete("/suppliers/{supplier_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_supplier(
    supplier_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("suppliers:delete")),
) -> None:
    supplier = db.get(Supplier, supplier_id)
    if supplier is None:
        raise HTTPException(status_code=404, detail="Fornecedor não encontrado.")
    db.delete(supplier)
    db.commit()


@router.get("/entries", response_model=list[StockEntryRead])
def list_stock_entries(
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> list[StockEntry]:
    entries = list(
        db.scalars(
            select(StockEntry)
            .options(selectinload(StockEntry.items))
            .order_by(StockEntry.created_at.desc(), StockEntry.id.desc())
            .limit(limit)
        ).all()
    )
    return entries


@router.get("/receipts", response_model=StockReceiptPage)
def list_receipts_page(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    status_filter: str | None = Query(default=None, alias="status"),
    source: str | None = Query(default=None),
    supplier_id: int | None = Query(default=None, ge=1),
    search: str | None = Query(default=None, max_length=120),
    created_from: datetime | None = Query(default=None),
    created_to: datetime | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> StockReceiptPage:
    """Server-side paginated inbox for the new receiving workspace."""

    filters = []
    if status_filter:
        filters.append(StockEntry.status == status_filter.strip().lower())
    if source:
        filters.append(StockEntry.source == source.strip().lower())
    if supplier_id is not None:
        filters.append(StockEntry.supplier_id == supplier_id)
    if created_from is not None or created_to is not None:
        date_columns = (
            StockEntry.created_at,
            StockEntry.issued_at,
            StockEntry.confirmed_at,
        )
        date_conditions = []
        for date_column in date_columns:
            bounds = []
            if created_from is not None:
                bounds.append(date_column >= created_from)
            if created_to is not None:
                bounds.append(date_column <= created_to)
            date_conditions.append(and_(*bounds))
        filters.append(or_(*date_conditions))
    if search and search.strip():
        term = f"%{search.strip()}%"
        filters.append(
            or_(
                StockEntry.invoice_number.ilike(term),
                StockEntry.invoice_key.ilike(term),
                StockEntry.supplier_name.ilike(term),
                StockEntry.supplier_document.ilike(term),
            )
        )
    base = select(StockEntry).where(*filters)
    total = int(db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    entries = list(
        db.scalars(
            base.options(selectinload(StockEntry.items))
            .order_by(StockEntry.created_at.desc(), StockEntry.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
    )
    return StockReceiptPage(items=entries, total=total, page=page, page_size=page_size)


@router.get("/receipts/summary", response_model=StockReceiptSummary)
def receipts_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> StockReceiptSummary:
    rows = db.execute(
        select(StockEntry.status, func.count(StockEntry.id)).group_by(StockEntry.status)
    ).all()
    counts = {str(status): int(total) for status, total in rows}
    pending = sum(counts.get(value, 0) for value in ("draft", "pending_product", "receiving", "awaiting_products"))
    divergences = sum(counts.get(value, 0) for value in ("divergence", "divergent", "under_review"))
    return StockReceiptSummary(
        all=sum(counts.values()),
        receiving=pending,
        pending_products=counts.get("pending_product", 0) + counts.get("awaiting_products", 0),
        divergences=divergences,
        confirmed=counts.get("confirmed", 0),
    )


def _receiving_session_read(session: ReceivingSession) -> ReceivingSessionRead:
    return ReceivingSessionRead(
        id=session.id,
        stock_entry_id=session.stock_entry_id,
        user_id=session.user_id,
        device_id=session.device_id,
        status=session.status,
        started_at=session.started_at,
        finished_at=session.finished_at,
        scan_count=len(session.scans),
        total_quantity=sum((scan.quantity for scan in session.scans), Decimal("0")),
    )


@router.post("/entries/{entry_id}/receiving-sessions", response_model=ReceivingSessionRead, status_code=status.HTTP_201_CREATED)
def start_receiving_session(
    entry_id: int,
    payload: ReceivingSessionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> ReceivingSessionRead:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    session = ReceivingSession(stock_entry_id=entry.id, user_id=current_user.id, device_id=payload.device_id)
    db.add(session)
    db.commit()
    db.refresh(session)
    return _receiving_session_read(session)


@router.get("/receiving-sessions/{session_id}", response_model=ReceivingSessionRead)
def get_receiving_session(
    session_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> ReceivingSessionRead:
    session = db.scalar(
        select(ReceivingSession)
        .options(selectinload(ReceivingSession.scans))
        .where(ReceivingSession.id == session_id)
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Sessao de conferencia nao encontrada.")
    return _receiving_session_read(session)


@router.post("/receiving-sessions/{session_id}/scans", response_model=ReceivingSessionRead)
def register_receiving_scan(
    session_id: int,
    payload: ReceivingScanCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> ReceivingSessionRead:
    session = db.scalar(
        select(ReceivingSession)
        .options(selectinload(ReceivingSession.scans))
        .where(ReceivingSession.id == session_id)
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Sessao de conferencia nao encontrada.")
    if session.status != "active":
        raise HTTPException(status_code=400, detail="Sessao de conferencia encerrada.")
    if db.scalar(select(ReceivingScan).where(ReceivingScan.idempotency_key == payload.idempotency_key)) is None:
        if payload.stock_entry_item_id is not None:
            if db.scalar(
                select(StockEntryItem).where(
                    StockEntryItem.id == payload.stock_entry_item_id,
                    StockEntryItem.stock_entry_id == session.stock_entry_id,
                )
            ) is None:
                raise HTTPException(status_code=400, detail="Item nao pertence a esta entrada.")
        session.scans.append(
            ReceivingScan(
                stock_entry_item_id=payload.stock_entry_item_id,
                idempotency_key=payload.idempotency_key,
                barcode=payload.barcode,
                quantity=payload.quantity,
                unit=payload.unit,
                batch_number=payload.batch_number,
                expiration_date=payload.expiration_date,
                condition=payload.condition,
                notes=payload.notes,
            )
        )
        db.commit()
        db.refresh(session)
    return _receiving_session_read(session)


@router.post("/receiving-sessions/{session_id}/finish", response_model=ReceivingSessionRead)
def finish_receiving_session(
    session_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> ReceivingSessionRead:
    session = db.scalar(
        select(ReceivingSession)
        .options(selectinload(ReceivingSession.scans))
        .where(ReceivingSession.id == session_id)
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Sessao de conferencia nao encontrada.")
    if session.status == "active":
        session.status = "finished"
        session.finished_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(session)
    return _receiving_session_read(session)


@router.post("/entries/open", response_model=StockEntryRead, status_code=status.HTTP_201_CREATED)
def create_open_stock_receiving(
    entry_in: StockEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    entry = _create_entry_record(db, entry_in, current_user, status_value="receiving")
    for item in entry.items:
        item.received_quantity = Decimal("0")
        if item.product_id is None:
            item.check_status = "pending_product"
    db.commit()
    return _entry_or_404(db, entry.id)


@router.get("/entries/{entry_id}", response_model=StockEntryRead)
def get_stock_entry(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> StockEntry:
    return _entry_or_404(db, entry_id)


@router.get("/entries/{entry_id}/audit", response_model=list[StockEntryAuditEventRead])
def list_stock_entry_audit(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:view")),
) -> list[StockEntryAuditEventRead]:
    _entry_or_404(db, entry_id)
    events = db.scalars(
        select(StockEntryAuditEvent)
        .where(StockEntryAuditEvent.stock_entry_id == entry_id)
        .order_by(StockEntryAuditEvent.created_at.desc(), StockEntryAuditEvent.id.desc())
    ).all()
    return [
        StockEntryAuditEventRead(
            id=event.id,
            stock_entry_id=event.stock_entry_id,
            stock_entry_item_id=event.stock_entry_item_id,
            user_id=event.user_id,
            user_name=event.user.name if event.user is not None else None,
            action=event.action,
            source=event.source,
            reason=event.reason,
            old_value=event.old_value,
            new_value=event.new_value,
            created_at=event.created_at,
        )
        for event in events
    ]


@router.post("/entries/{entry_id}/reprocess-matching", response_model=StockEntryRead)
def reprocess_stock_entry_matching(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    """Explicitly retry deterministic reconciliation without changing stock."""

    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    for item in entry.items:
        if item.product_id is not None:
            continue
        match = resolve_product_match(
            db,
            supplier_id=entry.supplier_id,
            supplier_product_code=item.supplier_product_code,
            commercial_gtin=item.barcode,
            tax_gtin=item.tax_gtin,
            internal_code=item.barcode,
            description=item.description,
        )
        if match.status == "matched" and match.product is not None:
            item.product_id = match.product.id
            item.check_status = "accepted"
            _apply_product_purchase_conversion_to_entry_item(item, match.product)
        elif match.status == "ambiguous":
            item.check_status = "ambiguous_product"
            item.check_notes = "Mais de um produto corresponde ao código informado; selecione explicitamente."
        else:
            item.check_status = "pending_product"
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries/draft", response_model=StockEntryRead, status_code=status.HTTP_201_CREATED)
def create_draft_stock_receiving(
    entry_in: StockEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    """Create a manual receiving draft without stock, cost or batch effects."""
    entry = _create_entry_record(db, entry_in, current_user, status_value="draft")
    db.commit()
    return _entry_or_404(db, entry.id)


@router.get(
    "/entries/{entry_id}/items/{item_id}/product-suggestions",
    response_model=list[StockEntryProductSuggestion],
)
def suggest_products_for_stock_entry_item(
    entry_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "stock:entries:create")),
) -> list[dict]:
    entry = _entry_or_404(db, entry_id)
    item = next((candidate for candidate in entry.items if candidate.id == item_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="Item da entrada nao encontrado.")
    match = resolve_product_match(
        db,
        supplier_id=entry.supplier_id,
        supplier_product_code=item.supplier_product_code,
        commercial_gtin=item.barcode,
        tax_gtin=item.tax_gtin,
        internal_code=item.barcode,
        description=item.description,
    )
    candidates = list(match.candidates)
    if match.product is not None:
        candidates = [match.product]
    if not candidates:
        # The resolver intentionally returns only strong description candidates.
        # Add token-aware suggestions so "cafe torrado 500g" also finds a
        # cadastro such as "Café Torrado - 500 g" without auto-linking it.
        words = {word for word in item.description.casefold().split() if len(word) >= 3}
        ranked: list[tuple[float, Product]] = []
        for product in db.scalars(select(Product).where(Product.active.is_(True))).all():
            name = product.name.casefold()
            overlap = sum(1 for word in words if word in name)
            score = overlap / max(len(words), 1)
            score = max(score, SequenceMatcher(None, item.description.casefold(), name).ratio())
            # A descrição só pode sugerir algo quando existe uma palavra
            # relevante em comum ou uma semelhança realmente alta. Isso evita
            # que produtos aleatórios, como açúcar ou biscoito, apareçam para
            # um café apenas porque os textos têm tamanho parecido.
            if overlap > 0 or score >= 0.70:
                ranked.append((score, product))
        ranked.sort(key=lambda pair: pair[0], reverse=True)
        candidates = [product for _, product in ranked[:8]]
        match_method = "description_suggestion"
    else:
        match_method = match.method or "code_or_gtin"
    results = []
    for product in candidates[:8]:
        if match_method == "description_suggestion":
            warning = "Sugestão por descrição. Confirme o código ou GTIN antes de associar."
        elif match.status == "ambiguous":
            warning = "Mais de um produto corresponde ao código/GTIN. Selecione explicitamente."
        elif normalize_product_code(item.barcode) == normalize_product_code(product.purchase_package_barcode):
            warning = "O XML usa o GTIN da caixa. O GTIN da unidade do cadastro será preservado."
        elif item.barcode and normalize_product_code(item.barcode) != normalize_product_code(product.barcode):
            warning = "O código/GTIN do XML é diferente do GTIN principal. Revise antes de confirmar; nada será substituído."
        else:
            warning = None
        results.append(
            {
                "product_id": product.id,
                "name": product.name,
                "internal_code": product.internal_code,
                "barcode": product.barcode,
                "purchase_package_barcode": product.purchase_package_barcode,
                "purchase_conversion_enabled": product.purchase_conversion_enabled,
                "purchase_package_factor": product.purchase_package_factor,
                "purchase_invoice_unit": product.purchase_invoice_unit,
                "unit": product.unit,
                "match_method": match_method,
                "warning": warning,
            }
        )
    return results


@router.post("/entries/{entry_id}/items/{item_id}/match", response_model=StockEntryRead)
def match_stock_entry_item(
    entry_id: int,
    item_id: int,
    payload: StockEntryItemMatchRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    """Apply an operator-approved product match and optionally remember it."""

    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    item = next((candidate for candidate in entry.items if candidate.id == item_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="Item da entrada nao encontrado.")
    product = db.get(Product, payload.product_id)
    if product is None or not product.active:
        raise HTTPException(status_code=404, detail="Produto ativo nao encontrado.")
    previous_product_id = item.product_id
    item.product_id = product.id
    item.check_status = "accepted"
    item.check_notes = None
    if payload.remember_supplier_link and entry.supplier_id and payload.supplier_product_code:
        code = normalize_product_code(payload.supplier_product_code)
        if code:
            link = db.scalar(
                select(SupplierProductLink).where(
                    SupplierProductLink.supplier_id == entry.supplier_id,
                    SupplierProductLink.supplier_product_code == code,
                )
            )
            if link is None:
                link = SupplierProductLink(
                    supplier_id=entry.supplier_id,
                    product_id=product.id,
                    supplier_product_code=code,
                )
                db.add(link)
            else:
                link.product_id = product.id
            link.supplier_description = payload.supplier_description or item.description
            link.commercial_gtin = normalize_product_code(payload.commercial_gtin or item.barcode)
            link.tax_gtin = normalize_product_code(payload.tax_gtin or item.tax_gtin)
            link.supplier_unit = payload.supplier_unit or item.invoice_unit or item.unit
            link.stock_unit = payload.stock_unit or product.unit
            link.conversion_factor = payload.conversion_factor
            link.last_cost = item.unit_cost
            link.last_seen_at = datetime.now(timezone.utc)
    if payload.conversion_factor is not None and payload.stock_unit:
        _apply_explicit_conversion_to_entry_item(
            item,
            factor=payload.conversion_factor,
            stock_unit=payload.stock_unit,
        )
    else:
        _apply_product_purchase_conversion_to_entry_item(item, product)
    _audit_entry(
        db,
        entry,
        current_user,
        "product_associated",
        item=item,
        old_value=f"product_id={previous_product_id}",
        new_value=f"product_id={product.id}; supplier_code={payload.supplier_product_code or item.supplier_product_code}; commercial_gtin={payload.commercial_gtin or item.barcode}",
        reason="Associação confirmada pelo operador.",
    )
    db.commit()
    return _entry_or_404(db, entry.id)


@router.put("/entries/{entry_id}", response_model=StockEntryRead)
def update_open_stock_entry(
    entry_id: int,
    entry_in: StockEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    supplier, supplier_document = _resolve_supplier(db, entry_in)
    entry.supplier_id = supplier.id if supplier else None
    entry.user_id = current_user.id
    entry.source = entry_in.source
    entry.invoice_key = entry_in.invoice_key
    entry.invoice_number = entry_in.invoice_number
    entry.invoice_series = entry_in.invoice_series
    entry.supplier_name = supplier.name if supplier else entry_in.supplier_name
    entry.supplier_document = supplier.document_number if supplier else supplier_document
    entry.notes = entry_in.notes
    entry.items.clear()
    db.flush()
    for item_in in entry_in.items:
        if item_in.product_id is not None and db.get(Product, item_in.product_id) is None:
            raise HTTPException(status_code=404, detail=f"Produto #{item_in.product_id} nao encontrado.")
        _append_stock_entry_item(entry, item_in)
    if entry.status != "draft":
        entry.status = "receiving"
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries", response_model=StockEntryRead, status_code=status.HTTP_201_CREATED)
def create_stock_entry(
    entry_in: StockEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:confirm")),
) -> StockEntry:
    entry = _create_entry_record(db, entry_in, current_user, status_value="receiving")
    _confirm_stock_entry(db, entry, current_user)
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries/{entry_id}/mobile-items", response_model=StockEntryRead)
def receive_stock_entry_mobile_item(
    entry_id: int,
    item_in: StockEntryMobileReceiveItem,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntry:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    barcode = item_in.barcode.strip() if item_in.barcode else None
    product = db.get(Product, item_in.product_id) if item_in.product_id is not None else None
    if product is None and barcode:
        product = _find_product_by_code(db, barcode)
    if product is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Produto nao cadastrado/vinculado. Cadastre ou vincule este item "
                "no computador antes de conferir pelo aplicativo."
            ),
        )
    product.barcode = product.barcode or barcode
    _apply_entry_tax_to_product(product, item_in)
    if item_in.sale_price is not None and (product.sale_price or Decimal("0")) <= 0:
        product.sale_price = item_in.sale_price
    received_quantity, received_unit, received_unit_cost = _normalize_mobile_received_quantity(
        product,
        barcode,
        item_in.quantity,
        item_in.unit,
        item_in.unit_cost,
    )
    check_status = item_in.check_status or "accepted"
    if check_status == "return":
        received_quantity = Decimal("0")

    existing_item = next(
        (
            item
            for item in entry.items
            if item.product_id == product.id
            or (barcode is not None and item.barcode == barcode)
        ),
        None,
    )
    if existing_item is None:
        entry.items.append(
            StockEntryItem(
                product_id=product.id,
                description=product.name,
                barcode=barcode or product.barcode or product.internal_code,
                quantity=Decimal("0"),
                received_quantity=received_quantity,
                unit=received_unit,
                unit_cost=received_unit_cost,
                total_cost=received_quantity * received_unit_cost,
                ncm=item_in.ncm,
                cfop=item_in.cfop,
                origin=item_in.origin,
                cst=item_in.cst,
                csosn=item_in.csosn,
                icms_rate=item_in.icms_rate,
                pis_rate=item_in.pis_rate,
                cofins_rate=item_in.cofins_rate,
                ipi_rate=item_in.ipi_rate,
                ibs_cbs_cst=item_in.ibs_cbs_cst,
                ibs_cbs_classification=item_in.ibs_cbs_classification,
                cbs_rate=item_in.cbs_rate,
                ibs_state_rate=item_in.ibs_state_rate,
                ibs_city_rate=item_in.ibs_city_rate,
                selective_tax_cst=item_in.selective_tax_cst,
                selective_tax_classification=item_in.selective_tax_classification,
                selective_tax_rate=item_in.selective_tax_rate,
                batch_number=item_in.batch_number,
                expiration_date=item_in.expiration_date,
                manufacturing_date=item_in.manufacturing_date,
                temperature_celsius=item_in.temperature_celsius,
                check_status=check_status,
                check_notes=item_in.check_notes,
            )
        )
    else:
        original_quantity = existing_item.invoice_quantity or existing_item.quantity
        original_unit = existing_item.invoice_unit or existing_item.unit
        factor = product.purchase_package_factor or Decimal("0")
        scanned_package_barcode = (
            _normalize_product_code(product.purchase_package_barcode) is not None
            and _normalize_product_code(product.purchase_package_barcode) == _normalize_product_code(barcode)
        )
        package_unit = (product.purchase_invoice_unit or "").strip().lower()
        original_is_package_unit = bool(package_unit) and (original_unit or "").strip().lower() == package_unit
        uses_purchase_conversion = (
            product.purchase_conversion_enabled
            and factor > 0
            and (scanned_package_barcode or original_is_package_unit or existing_item.package_conversion_factor is not None)
        )
        existing_item.product_id = product.id
        existing_item.description = product.name
        existing_item.barcode = existing_item.barcode or barcode or product.barcode
        if uses_purchase_conversion:
            existing_item.invoice_quantity = existing_item.invoice_quantity or original_quantity
            existing_item.invoice_unit = existing_item.invoice_unit or product.purchase_invoice_unit or original_unit
            existing_item.package_conversion_factor = existing_item.package_conversion_factor or factor
            existing_item.quantity = existing_item.invoice_quantity * existing_item.package_conversion_factor
        existing_item.received_quantity = received_quantity
        existing_item.unit = received_unit
        existing_item.unit_cost = received_unit_cost
        existing_item.total_cost = received_quantity * received_unit_cost
        existing_item.ncm = existing_item.ncm or item_in.ncm
        existing_item.cfop = existing_item.cfop or item_in.cfop
        existing_item.origin = existing_item.origin or item_in.origin
        existing_item.cst = existing_item.cst or item_in.cst
        existing_item.csosn = existing_item.csosn or item_in.csosn
        existing_item.icms_rate = existing_item.icms_rate if existing_item.icms_rate is not None else item_in.icms_rate
        existing_item.pis_rate = existing_item.pis_rate if existing_item.pis_rate is not None else item_in.pis_rate
        existing_item.cofins_rate = existing_item.cofins_rate if existing_item.cofins_rate is not None else item_in.cofins_rate
        existing_item.ipi_rate = existing_item.ipi_rate if existing_item.ipi_rate is not None else item_in.ipi_rate
        existing_item.ibs_cbs_cst = existing_item.ibs_cbs_cst or item_in.ibs_cbs_cst
        existing_item.ibs_cbs_classification = (
            existing_item.ibs_cbs_classification or item_in.ibs_cbs_classification
        )
        existing_item.cbs_rate = existing_item.cbs_rate if existing_item.cbs_rate is not None else item_in.cbs_rate
        existing_item.ibs_state_rate = (
            existing_item.ibs_state_rate if existing_item.ibs_state_rate is not None else item_in.ibs_state_rate
        )
        existing_item.ibs_city_rate = (
            existing_item.ibs_city_rate if existing_item.ibs_city_rate is not None else item_in.ibs_city_rate
        )
        existing_item.selective_tax_cst = existing_item.selective_tax_cst or item_in.selective_tax_cst
        existing_item.selective_tax_classification = (
            existing_item.selective_tax_classification or item_in.selective_tax_classification
        )
        existing_item.selective_tax_rate = (
            existing_item.selective_tax_rate if existing_item.selective_tax_rate is not None else item_in.selective_tax_rate
        )
        existing_item.batch_number = item_in.batch_number or existing_item.batch_number
        existing_item.expiration_date = item_in.expiration_date or existing_item.expiration_date
        existing_item.manufacturing_date = item_in.manufacturing_date or existing_item.manufacturing_date
        existing_item.temperature_celsius = item_in.temperature_celsius if item_in.temperature_celsius is not None else existing_item.temperature_celsius
        existing_item.check_status = check_status
        existing_item.check_notes = item_in.check_notes or existing_item.check_notes
    changed_item = existing_item or entry.items[-1]
    _audit_entry(
        db,
        entry,
        current_user,
        "item_checked",
        item=changed_item,
        new_value=f"quantity={received_quantity}; status={check_status}",
        reason=item_in.check_notes or "Conferência do item atualizada.",
    )
    entry.status = "receiving"
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries/{entry_id}/confirm", response_model=StockEntryRead)
def confirm_open_stock_entry(
    entry_id: int,
    return_all: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:confirm")),
) -> StockEntry:
    entry = _entry_or_404(db, entry_id)
    if return_all:
        for item in entry.items:
            item.check_status = "return"
        _audit_entry(
            db,
            entry,
            current_user,
            "full_return_requested",
            new_value="all_items=return",
            reason="Devolução integral selecionada na conferência.",
        )
    _confirm_stock_entry(db, entry, current_user)
    _audit_entry(
        db,
        entry,
        current_user,
        "receipt_confirmed",
        new_value=f"status={entry.status}",
        reason="Recebimento confirmado; estoque e custo atualizados.",
    )
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries/{entry_id}/devolution-draft", response_model=StockDevolutionDraftRead)
def create_stock_devolution_draft(
    entry_id: int,
    mode: str = Query(default="partial", pattern="^(partial|full)$"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:return")),
) -> dict:
    """Prepara uma NF-e de devolução, sem autorizar ou transmitir automaticamente."""
    entry = _entry_or_404(db, entry_id)
    if entry.supplier_id is None:
        raise HTTPException(status_code=400, detail="A entrada precisa ter fornecedor cadastrado.")
    supplier = db.get(Supplier, entry.supplier_id)
    if supplier is None or not supplier.document_number:
        raise HTTPException(status_code=400, detail="Cadastre o CNPJ do fornecedor antes de preparar a devolução.")
    setting = db.scalar(select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc()))
    if setting is None or not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e não está habilitada para esta empresa.")

    draft_items: list[dict] = []
    for item in entry.items:
        expected = item.invoice_quantity or item.quantity or Decimal("0")
        received = item.received_quantity or Decimal("0")
        quantity = expected if mode == "full" else max(expected - received, Decimal("0"))
        if item.check_status == "return" and mode == "partial":
            quantity = expected
        # A missing product is allowed here only for a quantity that will be
        # returned.  The receiving confirmation itself still blocks any
        # positive quantity for an unassociated item.  Keeping the XML item in
        # the draft preserves the fiscal description/codes so the return is
        # visible and can be completed after the product is registered.
        if quantity <= 0:
            continue
        unit_price = item.unit_cost or Decimal("0")
        reason = "Devolução integral da nota" if mode == "full" else "Diferença não recebida na conferência"
        draft_items.append({
            "stock_entry_item_id": item.id,
            "product_id": item.product_id,
            "description": item.description,
            "quantity": quantity,
            "unit": item.unit,
            "unit_price": unit_price,
            "total_price": quantity * unit_price,
            "reason": reason,
            "ncm": item.ncm,
            "cfop": item.cfop,
            "origin": item.origin,
            "cst": item.cst,
            "csosn": item.csosn,
        })
    if not draft_items:
        raise HTTPException(status_code=400, detail="Não há itens ou diferenças para devolver.")

    document = FiscalDocument(
        document_type="nfe",
        model="55",
        environment=setting.environment,
        status="draft",
        supplier_id=supplier.id,
        recipient_document=supplier.document_number,
        recipient_name=supplier.name,
        operation_nature="DEVOLUÇÃO DE COMPRA",
        finality="4",
        payment_condition="outros",
        fiscal_notes=f"Devolução vinculada à NF {entry.invoice_number or entry.id}. Chave original: {entry.invoice_key or 'não informada'}.",
        stock_deduction_on_authorize=False,
        sefaz_message="Rascunho de devolução preparado no recebimento. Ainda não autorizado.",
    )
    db.add(document)
    db.flush()
    item_by_id = {item.id: item for item in entry.items}
    for item_data in draft_items:
        source_item = item_by_id[item_data["stock_entry_item_id"]]
        db.add(FiscalDocumentItem(
            fiscal_document_id=document.id,
            fiscal_product_id=item_data["product_id"],
            original_description=item_data["description"],
            fiscal_description=item_data["description"],
            quantity=item_data["quantity"],
            unit=item_data["unit"],
            unit_price=item_data["unit_price"],
            total_price=item_data["total_price"],
            barcode=source_item.barcode,
            included=True,
            adjustment_reason=item_data["reason"],
            ncm=item_data["ncm"],
            cfop=item_data["cfop"],
            origin=item_data["origin"],
            cst=item_data["cst"],
            csosn=item_data["csosn"],
            ibs_cbs_cst=source_item.ibs_cbs_cst,
            ibs_cbs_classification=source_item.ibs_cbs_classification,
            cbs_rate=source_item.cbs_rate,
            ibs_state_rate=source_item.ibs_state_rate,
            ibs_city_rate=source_item.ibs_city_rate,
            selective_tax_cst=source_item.selective_tax_cst,
            selective_tax_classification=source_item.selective_tax_classification,
            selective_tax_rate=source_item.selective_tax_rate,
            created_by_user_id=current_user.id,
        ))
    _audit_entry(
        db,
        entry,
        current_user,
        "devolution_draft_prepared",
        new_value=f"fiscal_document_id={document.id}; mode={mode}; items={len(draft_items)}",
        reason="Rascunho fiscal preparado a partir da conferência.",
    )
    db.commit()
    return {
        "fiscal_document_id": document.id,
        "stock_entry_id": entry.id,
        "mode": mode,
        "status": document.status,
        "supplier_name": supplier.name,
        "supplier_document": supplier.document_number,
        "original_invoice_number": entry.invoice_number,
        "original_invoice_key": entry.invoice_key,
        "total_amount": sum((item["total_price"] for item in draft_items), Decimal("0")),
        "items": draft_items,
    }


@router.post("/entries/{entry_id}/items/{item_id}/lots", response_model=StockEntryItemLotRead)
def add_stock_entry_item_lot(
    entry_id: int,
    item_id: int,
    payload: StockEntryItemLotCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntryItemLot:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    item = next((candidate for candidate in entry.items if candidate.id == item_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="Item da entrada nao encontrado.")
    lot = StockEntryItemLot(stock_entry_item_id=item.id, **payload.model_dump())
    db.add(lot)
    db.commit()
    db.refresh(lot)
    return lot


@router.put("/entries/{entry_id}/items/{item_id}/lots/{lot_id}", response_model=StockEntryItemLotRead)
def update_stock_entry_item_lot(
    entry_id: int,
    item_id: int,
    lot_id: int,
    payload: StockEntryItemLotCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> StockEntryItemLot:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    lot = db.scalar(
        select(StockEntryItemLot)
        .join(StockEntryItem, StockEntryItem.id == StockEntryItemLot.stock_entry_item_id)
        .where(
            StockEntryItemLot.id == lot_id,
            StockEntryItemLot.stock_entry_item_id == item_id,
            StockEntryItem.stock_entry_id == entry_id,
        )
    )
    if lot is None:
        raise HTTPException(status_code=404, detail="Lote do item nao encontrado.")
    for key, value in payload.model_dump().items():
        setattr(lot, key, value)
    db.commit()
    db.refresh(lot)
    return lot


@router.delete("/entries/{entry_id}/items/{item_id}/lots/{lot_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_stock_entry_item_lot(
    entry_id: int,
    item_id: int,
    lot_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> None:
    entry = _entry_or_404(db, entry_id)
    if entry.status == "confirmed":
        raise HTTPException(status_code=400, detail="Entrada ja confirmada.")
    lot = db.scalar(
        select(StockEntryItemLot)
        .join(StockEntryItem, StockEntryItem.id == StockEntryItemLot.stock_entry_item_id)
        .where(
            StockEntryItemLot.id == lot_id,
            StockEntryItemLot.stock_entry_item_id == item_id,
            StockEntryItem.stock_entry_id == entry_id,
        )
    )
    if lot is None:
        raise HTTPException(status_code=404, detail="Lote do item nao encontrado.")
    db.delete(lot)
    db.commit()


@router.post("/entries/{entry_id}/reverse", response_model=StockEntryRead)
def reverse_confirmed_stock_entry(
    entry_id: int,
    payload: StockEntryReversalRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:reverse")),
) -> StockEntry:
    """Reverse a confirmed entry through inverse stock movements, never by editing history."""

    entry = _entry_or_404(db, entry_id)
    if entry.status != "confirmed":
        raise HTTPException(status_code=400, detail="Somente entradas confirmadas podem ser estornadas.")
    if entry.reversed_at is not None or entry.status == "reversed":
        raise HTTPException(status_code=400, detail="Esta entrada ja foi estornada.")
    for item in entry.items:
        if item.check_status != "accepted" or not item.product_id:
            continue
        quantity = item.received_quantity or Decimal("0")
        if quantity <= 0:
            continue
        product = db.get(Product, item.product_id)
        if product is None:
            raise HTTPException(status_code=400, detail=f"Produto do item '{item.description}' nao encontrado.")
        if product.stock_quantity < quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Estoque insuficiente para estornar '{product.name}'. Ajuste o saldo antes de continuar.",
            )
        quantity_before = product.stock_quantity
        unit_cost, total_value = apply_stock_out(product, quantity)
        return_to_batch(
            db,
            product,
            quantity,
            source_type="stock_entry_reversal",
            source_id=entry.id,
            source_number=entry.invoice_number,
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=current_user.id,
                movement_type="purchase_in_reversal",
                source_type="stock_entry_reversal",
                source_id=entry.id,
                source_number=entry.invoice_number,
                quantity_delta=-quantity,
                quantity_before=quantity_before,
                quantity_after=product.stock_quantity,
                unit=product.unit,
                unit_price=unit_cost,
                total_value=total_value,
                reason="Estorno de entrada de mercadoria",
                notes=payload.reason,
            )
        )
    entry.status = "reversed"
    entry.reversed_at = datetime.now(timezone.utc)
    entry.reversal_reason = payload.reason
    _audit_entry(
        db,
        entry,
        current_user,
        "receipt_reversed",
        source="web",
        reason=payload.reason,
        old_value="status=confirmed",
        new_value="status=reversed",
    )
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/nfe/xml/preview", response_model=NfeXmlPreview)
def preview_nfe_xml(
    payload: NfeXmlImportRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> NfeXmlPreview:
    try:
        parsed = parse_nfe_xml(payload.xml_content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    supplier_document = _only_digits(parsed.get("supplier_document"))
    supplier = None
    if supplier_document is not None:
        supplier = db.scalar(select(Supplier).where(Supplier.document_number == supplier_document))

    preview_items: list[NfeXmlPreviewItem] = []
    for item in parsed["items"]:
        barcode = item.get("barcode")
        match = resolve_product_match(
            db,
            supplier_id=supplier.id if supplier else None,
            supplier_product_code=str(item.get("supplier_product_code") or "") or None,
            commercial_gtin=str(barcode) if barcode is not None else None,
            tax_gtin=str(item.get("tax_gtin") or "") or None,
            internal_code=None,
            description=str(item.get("description") or ""),
        )
        preview_items.append(
            NfeXmlPreviewItem(
                product_id=match.product.id if match.product else None,
                product_name=match.product.name if match.product else None,
                matching_status=match.status,
                matching_method=match.method,
                match_suggestions=[product.id for product in match.candidates],
                **item,
            )
        )

    return NfeXmlPreview(
        supplier_id=supplier.id if supplier else None,
        supplier_name=parsed.get("supplier_name"),
        supplier_document=supplier_document,
        invoice_key=parsed.get("invoice_key"),
        invoice_number=parsed.get("invoice_number"),
        invoice_series=parsed.get("invoice_series"),
        items=preview_items,
    )


@router.post("/nfe/key/download")
def download_nfe_by_key(
    payload: NfeKeyDownloadRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:create")),
) -> dict[str, str]:
    fiscal_setting = db.scalar(select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc()))
    if (
        fiscal_setting is None
        or not fiscal_setting.certificate_encrypted_blob
        or not fiscal_setting.certificate_password_encrypted
    ):
        return {
            "status": "certificate_required",
            "message": (
                "Baixa automatica por chave da NF-e precisa do Certificado Digital A1 "
                "da empresa cadastrado no modulo Fiscal."
            ),
        }
    return {
        "status": "sefaz_integration_pending",
        "message": (
            "Certificado A1 encontrado e protegido. A comunicacao real com a SEFAZ "
            "ainda precisa da etapa de homologacao do webservice de distribuicao de DF-e."
        ),
    }

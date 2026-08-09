from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.product import Product
from app.models.fiscal import CompanyFiscalSetting
from app.models.stock_entry import StockEntry, StockEntryItem
from app.models.stock_movement import StockMovement
from app.models.supplier import Supplier
from app.models.user import User
from app.schemas.stock_entry import (
    NfeKeyDownloadRequest,
    NfeXmlImportRequest,
    NfeXmlPreview,
    NfeXmlPreviewItem,
    StockEntryCreate,
    StockEntryItemCreate,
    StockEntryMobileReceiveItem,
    StockEntryRead,
)
from app.schemas.supplier import SupplierCreate, SupplierRead, SupplierUpdate
from app.services.access_control import user_has_permission
from app.services.nfe_xml import parse_nfe_xml
from app.services.product_batches import upsert_product_batch
from app.services.product_costs import apply_stock_in
from app.services.fiscal_assistant import learn_from_stock_entry_item
from app.services.fiscal_stock import refresh_many_product_fiscal_balances

router = APIRouter()


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
        .options(selectinload(StockEntry.items))
        .where(StockEntry.id == entry_id)
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Entrada de estoque nao encontrada.")
    if _relink_pending_entry_items(db, entry):
        db.commit()
        db.refresh(entry)
    return entry


def _calculate_entry_item_total(item: StockEntryItem) -> Decimal:
    return (item.received_quantity or Decimal("0")) * item.unit_cost


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
        if check_status == "accepted" and product is None:
            raise HTTPException(
                status_code=400,
                detail=f"Item '{item.description}' precisa estar vinculado a um produto antes de confirmar.",
            )
        if check_status == "accepted" and product is not None:
            accepted_product_ids.add(product.id)
            _apply_entry_tax_to_product(product, item)
            learn_from_stock_entry_item(db, item, entry=entry, source=entry.source or "stock_entry")
            accepted_total = _calculate_entry_item_total(item)
            quantity_before = product.stock_quantity
            unit_cost, effective_total = apply_stock_in(product, received_quantity, accepted_total)
            product.purchase_total_cost = effective_total or accepted_total
            product.purchase_quantity = received_quantity
            total_amount += effective_total or accepted_total
            upsert_product_batch(
                db,
                product,
                received_quantity,
                batch_number=item.batch_number,
                expiration_date=item.expiration_date,
                source_type="stock_entry",
                source_id=entry.id,
                source_number=entry.invoice_number,
                supplier_name=entry.supplier_name,
                invoice_number=entry.invoice_number,
                invoice_series=entry.invoice_series,
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
            invoice_quantity=item_in.invoice_quantity,
            invoice_unit=item_in.invoice_unit,
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
    changed = False
    for entry in entries:
        changed = _relink_pending_entry_items(db, entry) or changed
    if changed:
        db.commit()
        entries = list(
            db.scalars(
                select(StockEntry)
                .options(selectinload(StockEntry.items))
                .order_by(StockEntry.created_at.desc(), StockEntry.id.desc())
                .limit(limit)
            ).all()
        )
    return entries


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
                check_status="accepted",
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
        existing_item.check_status = "accepted"
        existing_item.check_notes = item_in.check_notes or existing_item.check_notes
    entry.status = "receiving"
    db.commit()
    return _entry_or_404(db, entry.id)


@router.post("/entries/{entry_id}/confirm", response_model=StockEntryRead)
def confirm_open_stock_entry(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:entries:confirm")),
) -> StockEntry:
    entry = _entry_or_404(db, entry_id)
    _confirm_stock_entry(db, entry, current_user)
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
        product = _find_product_by_code(db, str(barcode) if barcode is not None else None)
        preview_items.append(
            NfeXmlPreviewItem(
                product_id=product.id if product else None,
                product_name=product.name if product else None,
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

from datetime import date, datetime, time

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.product import Product
from app.models.product_composition import ProductCompositionItem
from app.models.product_batch import ProductBatch
from app.models.stock_entry import StockEntry, StockEntryItem
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.product import ProductCreate, ProductRead, ProductUpdate
from app.schemas.product_composition import (
    ProductCompositionItemCreate,
    ProductCompositionItemRead,
    ProductCompositionItemUpdate,
)
from app.schemas.product_batch import ProductBatchRead
from app.schemas.stock_movement import (
    StockMovementRead,
    StockWithdrawalCreate,
    StockWithdrawalRead,
)
from app.services.product_batches import ensure_initial_product_batch, list_available_batches
from app.services.product_batches import apply_batch_out
from app.services.product_costs import apply_stock_out, base_unit_cost, refresh_inventory_value
from app.services.fiscal_assistant import learn_from_product
from app.services.fiscal_stock import refresh_many_product_fiscal_balances
from app.services.unit_conversion import are_units_compatible

router = APIRouter()

COMPOSITION_COMPONENT_TYPES = {"materia_prima", "insumo", "embalagem", "peca"}
STOCK_WITHDRAWAL_REASON_LABELS = {
    "loss_damage": "Perda ou avaria",
    "expired": "Produto vencido",
    "internal_consumption": "Consumo interno",
    "employee_meal": "Alimentacao da equipe",
    "production_use": "Uso na producao",
    "sample_gift": "Amostra ou brinde",
    "theft": "Furto ou desaparecimento",
    "inventory_adjustment": "Ajuste de inventario",
    "other": "Outros",
}


def _normalize_gtin(value: str | None) -> str | None:
    cleaned = "".join(ch for ch in (value or "").strip() if ch.isdigit())
    if not cleaned:
        return None
    if cleaned.upper() == "SEMGTIN":
        return None
    return cleaned


def _ensure_unique_gtin(db: Session, barcode: str | None, product_id: int | None = None) -> None:
    gtin = _normalize_gtin(barcode)
    if gtin is None:
        return
    query = select(Product).where(
        (Product.barcode == gtin) | (Product.purchase_package_barcode == gtin)
    )
    if product_id is not None:
        query = query.where(Product.id != product_id)
    existing = db.scalar(query)
    if existing is not None:
        raise HTTPException(
            status_code=409,
            detail=f"GTIN/codigo de barras ja cadastrado no produto: {existing.name}.",
        )


def _validate_offer_period(data: dict) -> None:
    start_at = data.get("offer_start_at")
    end_at = data.get("offer_end_at")
    price = data.get("offer_price")
    if price is not None and (start_at is None or end_at is None):
        raise HTTPException(
            status_code=400,
            detail="Oferta precisa ter data/hora de inicio e fim.",
        )
    if start_at is not None and end_at is not None and end_at <= start_at:
        raise HTTPException(
            status_code=400,
            detail="Fim da oferta precisa ser depois do inicio.",
        )


@router.post("", response_model=ProductRead, status_code=status.HTTP_201_CREATED)
def create_product(
    product_in: ProductCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:create")),
) -> Product:
    data = product_in.model_dump()
    data["barcode"] = _normalize_gtin(data.get("barcode"))
    data["purchase_package_barcode"] = _normalize_gtin(data.get("purchase_package_barcode"))
    _ensure_unique_gtin(db, data.get("barcode"))
    _ensure_unique_gtin(db, data.get("purchase_package_barcode"))
    _validate_offer_period(data)
    product = Product(**data)
    refresh_inventory_value(product, force_from_purchase=True)
    db.add(product)
    db.flush()
    learn_from_product(db, product)
    ensure_initial_product_batch(db, product)
    db.commit()
    db.refresh(product)
    return product


def _attach_receipt_summary(db: Session, products: list[Product]) -> None:
    product_ids = [product.id for product in products]
    if not product_ids:
        return
    refresh_many_product_fiscal_balances(db, set(product_ids))
    rows = db.scalars(
        select(ProductBatch)
        .where(
            ProductBatch.product_id.in_(product_ids),
            ProductBatch.active.is_(True),
            ProductBatch.quantity > 0,
        )
        .order_by(
            ProductBatch.expiration_date.asc().nulls_last(),
            ProductBatch.created_at.desc(),
            ProductBatch.id.desc(),
        )
    ).all()
    by_product: dict[int, ProductBatch] = {}
    for batch in rows:
        by_product.setdefault(batch.product_id, batch)
    for product in products:
        batch = by_product.get(product.id)
        if batch is None:
            product.nearest_batch_number = product.initial_batch_number
            product.nearest_expiration_date = product.initial_expiration_date
            product.last_receipt_supplier_name = None
            product.last_receipt_invoice_number = None
            continue
        product.nearest_batch_number = batch.batch_number or product.initial_batch_number
        product.nearest_expiration_date = batch.expiration_date or product.initial_expiration_date
        product.last_receipt_supplier_name = batch.supplier_name
        product.last_receipt_invoice_number = batch.invoice_number


@router.get("", response_model=list[ProductRead])
def list_products(
    product_type: str | None = Query(default=None),
    active: bool | None = Query(default=None),
    q: str | None = Query(default=None, min_length=1),
    limit: int = Query(default=500, ge=1, le=1000),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "products:view",
            "stock:withdraw",
            "sales:view",
            "sales:create",
            "service_orders:view",
            "service_orders:update",
        )
    ),
) -> list[Product]:
    query = select(Product).order_by(Product.name)
    if product_type is not None:
        query = query.where(Product.product_type == product_type)
    if active is not None:
        query = query.where(Product.active == active)
    if q is not None and q.strip():
        term = q.strip()
        like = f"%{term}%"
        digits = "".join(ch for ch in term if ch.isdigit())
        filters = [
            Product.name.ilike(like),
            Product.internal_code.ilike(like),
            Product.barcode.ilike(like),
            Product.purchase_package_barcode.ilike(like),
            Product.brand.ilike(like),
            Product.category.ilike(like),
        ]
        if digits:
            digit_like = f"%{digits}%"
            filters.extend(
                [
                    Product.barcode.ilike(digit_like),
                    Product.internal_code.ilike(digit_like),
                    Product.purchase_package_barcode.ilike(digit_like),
                ]
            )
        query = query.where(or_(*filters))
    query = query.limit(limit)
    products = list(db.scalars(query).all())
    _attach_receipt_summary(db, products)
    return products


@router.get("/lookup/by-code", response_model=ProductRead)
def lookup_product_by_code(
    code: str = Query(min_length=1),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "products:view",
            "stock:withdraw",
            "sales:view",
            "sales:create",
            "service_orders:view",
            "service_orders:update",
        )
    ),
) -> Product:
    normalized = code.strip()
    product = db.scalar(
        select(Product).where(
            (Product.barcode == normalized)
            | (Product.internal_code == normalized)
            | (Product.purchase_package_barcode == normalized)
        )
    )
    if product is None:
        raise HTTPException(status_code=404, detail="Produto nao encontrado pelo codigo.")
    _attach_receipt_summary(db, [product])
    return product


@router.get("/stock-withdrawals/recent", response_model=list[StockWithdrawalRead])
def list_recent_stock_withdrawals(
    date_from: date | None = Query(default=None),
    date_to: date | None = Query(default=None),
    product_id: int | None = Query(default=None),
    reason: str | None = Query(default=None),
    user_id: int | None = Query(default=None),
    limit: int = Query(default=200, ge=1, le=1000),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:withdraw")),
) -> list[StockWithdrawalRead]:
    query = select(StockMovement).where(
        StockMovement.source_type == "stock_withdrawal"
    )
    if date_from is not None:
        query = query.where(
            StockMovement.created_at >= datetime.combine(date_from, time.min)
        )
    if date_to is not None:
        query = query.where(
            StockMovement.created_at <= datetime.combine(date_to, time.max)
        )
    if product_id is not None:
        query = query.where(StockMovement.product_id == product_id)
    if reason is not None and reason.strip():
        query = query.where(StockMovement.reason == reason.strip())
    if user_id is not None:
        query = query.where(StockMovement.user_id == user_id)
    movements = list(
        db.scalars(
            query.order_by(
                StockMovement.created_at.desc(), StockMovement.id.desc()
            ).limit(limit)
        ).all()
    )
    return [
        StockWithdrawalRead(
            **StockMovementRead.model_validate(movement).model_dump(),
            product_name=movement.product.name,
            user_name=movement.user.name if movement.user is not None else None,
        )
        for movement in movements
    ]


@router.get("/{product_id}", response_model=ProductRead)
def get_product(
    product_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "products:view",
            "sales:view",
            "sales:create",
            "service_orders:view",
            "service_orders:update",
        )
    ),
) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    _attach_receipt_summary(db, [product])
    return product


@router.get("/{product_id}/stock-movements", response_model=list[StockMovementRead])
def list_product_stock_movements(
    product_id: int,
    limit: int = Query(default=100, ge=1, le=300),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:view", "products:view")),
) -> list[StockMovementRead]:
    if db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    query = (
        select(StockMovement)
        .where(StockMovement.product_id == product_id)
        .order_by(StockMovement.created_at.desc(), StockMovement.id.desc())
        .limit(limit)
    )
    movements = list(db.scalars(query).all())
    entry_ids = [
        movement.source_id
        for movement in movements
        if movement.source_type == "stock_entry" and movement.source_id is not None
    ]
    receipt_items: dict[int, tuple[StockEntry, StockEntryItem]] = {}
    if entry_ids:
        rows = db.execute(
            select(StockEntry, StockEntryItem)
            .join(StockEntryItem, StockEntryItem.stock_entry_id == StockEntry.id)
            .where(
                StockEntry.id.in_(entry_ids),
                StockEntryItem.product_id == product_id,
                StockEntryItem.check_status == "accepted",
            )
        ).all()
        for entry, item in rows:
            receipt_items.setdefault(entry.id, (entry, item))

    result: list[StockMovementRead] = []
    for movement in movements:
        data = StockMovementRead.model_validate(movement).model_dump()
        if movement.source_type == "stock_entry" and movement.source_id in receipt_items:
            entry, item = receipt_items[movement.source_id]
            data.update(
                {
                    "supplier_name": entry.supplier_name,
                    "supplier_document": entry.supplier_document,
                    "invoice_key": entry.invoice_key,
                    "invoice_number": entry.invoice_number,
                    "invoice_series": entry.invoice_series,
                    "batch_number": item.batch_number,
                    "expiration_date": item.expiration_date,
                    "received_quantity": item.received_quantity,
                    "check_status": item.check_status,
                    "check_notes": item.check_notes,
                }
            )
        result.append(StockMovementRead(**data))
    return result


@router.post(
    "/{product_id}/stock-withdrawals",
    response_model=StockMovementRead,
    status_code=status.HTTP_201_CREATED,
)
def create_stock_withdrawal(
    product_id: int,
    withdrawal_in: StockWithdrawalCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("stock:withdraw")),
) -> StockMovement:
    product = db.scalar(
        select(Product).where(Product.id == product_id).with_for_update()
    )
    if product is None:
        raise HTTPException(status_code=404, detail="Produto nao encontrado.")
    if product.product_type == "servico":
        raise HTTPException(
            status_code=400,
            detail="Servicos nao possuem saldo de estoque para baixa.",
        )
    if not product.active:
        raise HTTPException(
            status_code=400,
            detail="Nao e possivel dar baixa em produto inativo.",
        )
    if withdrawal_in.quantity > product.stock_quantity:
        raise HTTPException(
            status_code=409,
            detail=(
                f"Saldo insuficiente. Disponivel: "
                f"{product.stock_quantity} {product.unit}."
            ),
        )

    quantity_before = product.stock_quantity
    unit_cost, total_cost = apply_stock_out(product, withdrawal_in.quantity)
    reason = STOCK_WITHDRAWAL_REASON_LABELS[withdrawal_in.reason_code]
    movement = StockMovement(
        product_id=product.id,
        user_id=current_user.id,
        movement_type="manual_out",
        source_type="stock_withdrawal",
        quantity_delta=-withdrawal_in.quantity,
        quantity_before=quantity_before,
        quantity_after=product.stock_quantity,
        unit=product.unit,
        unit_price=unit_cost,
        total_value=total_cost,
        reason=reason,
        notes=withdrawal_in.notes,
    )
    db.add(movement)
    db.flush()
    movement.source_id = movement.id
    movement.source_number = f"B{movement.id}"
    apply_batch_out(
        db,
        product,
        withdrawal_in.quantity,
        source_type="stock_withdrawal",
        source_id=movement.id,
        source_number=movement.source_number,
    )
    db.commit()
    db.refresh(movement)
    return movement


@router.get("/{product_id}/batches", response_model=list[ProductBatchRead])
def list_product_batches(
    product_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:batches:view", "stock:view")),
) -> list[ProductBatch]:
    if db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    return list_available_batches(db, product_id)


def _composition_read(item: ProductCompositionItem) -> ProductCompositionItemRead:
    component = item.component_product
    return ProductCompositionItemRead(
        id=item.id,
        product_id=item.product_id,
        component_product_id=item.component_product_id,
        component_name=component.name,
        component_internal_code=component.internal_code,
        component_unit=component.unit,
        component_unit_cost=base_unit_cost(component),
        quantity=item.quantity,
        unit=item.unit,
        waste_percent=item.waste_percent,
        notes=item.notes,
        created_at=item.created_at,
    )


@router.get("/{product_id}/composition", response_model=list[ProductCompositionItemRead])
def list_product_composition(
    product_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:view", "products:view")),
) -> list[ProductCompositionItemRead]:
    if db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    query = (
        select(ProductCompositionItem)
        .where(ProductCompositionItem.product_id == product_id)
        .order_by(ProductCompositionItem.id)
    )
    return [_composition_read(item) for item in db.scalars(query).all()]


@router.post(
    "/{product_id}/composition",
    response_model=ProductCompositionItemRead,
    status_code=status.HTTP_201_CREATED,
)
def create_product_composition_item(
    product_id: int,
    item_in: ProductCompositionItemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:update")),
) -> ProductCompositionItemRead:
    if db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    component = db.get(Product, item_in.component_product_id)
    if component is None:
        raise HTTPException(status_code=404, detail="Materia-prima/insumo nao encontrado.")
    if component.product_type not in COMPOSITION_COMPONENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Ficha tecnica aceita apenas materia-prima, insumo, embalagem ou peca.",
        )
    if component.id == product_id:
        raise HTTPException(status_code=400, detail="O item nao pode compor ele mesmo.")
    if not are_units_compatible(item_in.unit, component.unit):
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unidade {item_in.unit} incompativel com a unidade de estoque "
                f"do componente ({component.unit})."
            ),
        )

    existing = db.scalar(
        select(ProductCompositionItem).where(
            ProductCompositionItem.product_id == product_id,
            ProductCompositionItem.component_product_id == component.id,
        )
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Este componente ja esta na ficha tecnica.")

    item = ProductCompositionItem(product_id=product_id, **item_in.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return _composition_read(item)


@router.put(
    "/{product_id}/composition/{item_id}",
    response_model=ProductCompositionItemRead,
)
def update_product_composition_item(
    product_id: int,
    item_id: int,
    item_in: ProductCompositionItemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:update")),
) -> ProductCompositionItemRead:
    item = db.scalar(
        select(ProductCompositionItem).where(
            ProductCompositionItem.id == item_id,
            ProductCompositionItem.product_id == product_id,
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Item da ficha tecnica nao encontrado.")

    update_data = item_in.model_dump(exclude_unset=True)
    if "unit" in update_data and not are_units_compatible(update_data["unit"], item.component_product.unit):
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unidade {update_data['unit']} incompativel com a unidade de estoque "
                f"do componente ({item.component_product.unit})."
            ),
        )

    for field, value in update_data.items():
        setattr(item, field, value)

    db.commit()
    db.refresh(item)
    return _composition_read(item)


@router.delete(
    "/{product_id}/composition/{item_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_product_composition_item(
    product_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:update")),
) -> None:
    item = db.scalar(
        select(ProductCompositionItem).where(
            ProductCompositionItem.id == item_id,
            ProductCompositionItem.product_id == product_id,
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Item da ficha tecnica nao encontrado.")
    db.delete(item)
    db.commit()


@router.put("/{product_id}", response_model=ProductRead)
def update_product(
    product_id: int,
    product_in: ProductUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:update")),
) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")

    update_data = product_in.model_dump(exclude_unset=True)
    if "barcode" in update_data:
        update_data["barcode"] = _normalize_gtin(update_data.get("barcode"))
        _ensure_unique_gtin(db, update_data.get("barcode"), product_id=product.id)
    if "purchase_package_barcode" in update_data:
        update_data["purchase_package_barcode"] = _normalize_gtin(
            update_data.get("purchase_package_barcode")
        )
        _ensure_unique_gtin(db, update_data.get("purchase_package_barcode"), product_id=product.id)
    offer_data = {
        "offer_price": update_data.get("offer_price", product.offer_price),
        "offer_start_at": update_data.get("offer_start_at", product.offer_start_at),
        "offer_end_at": update_data.get("offer_end_at", product.offer_end_at),
    }
    _validate_offer_period(offer_data)
    purchase_cost_changed = (
        "purchase_total_cost" in update_data
        and update_data["purchase_total_cost"] != product.purchase_total_cost
    )
    purchase_quantity_changed = (
        "purchase_quantity" in update_data
        and update_data["purchase_quantity"] != product.purchase_quantity
    )
    average_cost_changed = (
        "average_cost" in update_data
        and update_data["average_cost"] != product.average_cost
    )
    for field, value in update_data.items():
        setattr(product, field, value)

    if average_cost_changed:
        refresh_inventory_value(product)
    elif purchase_cost_changed or purchase_quantity_changed:
        refresh_inventory_value(product, force_from_purchase=True)
    elif "stock_quantity" in update_data:
        refresh_inventory_value(product)

    learn_from_product(db, product)
    ensure_initial_product_batch(db, product)
    db.commit()
    db.refresh(product)
    return product


@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(
    product_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:delete")),
) -> None:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")
    db.delete(product)
    db.commit()

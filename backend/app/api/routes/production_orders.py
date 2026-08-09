from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.product import Product
from app.models.product_composition import ProductCompositionItem
from app.models.production_order import ProductionOrder, ProductionOrderComponent
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.production_order import (
    ProductionOrderCancel,
    ProductionOrderComplete,
    ProductionOrderCreate,
    ProductionOrderComponentPreview,
    ProductionOrderPreview,
    ProductionOrderRead,
)
from app.services.product_batches import apply_batch_out, return_to_batch, upsert_product_batch
from app.services.product_costs import apply_stock_in, apply_stock_out, base_unit_cost
from app.services.unit_conversion import convert_quantity

router = APIRouter()

OPEN_STATUSES = {"planejada", "em_producao"}
FINAL_STATUSES = {"concluida", "cancelada"}


def production_order_number(order_id: int) -> str:
    return f"OP{order_id}"


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _read_order(order: ProductionOrder) -> ProductionOrderRead:
    return ProductionOrderRead(
        id=order.id,
        number=order.number,
        product_id=order.product_id,
        product_name=order.product.name,
        user_id=order.user_id,
        completed_by_user_id=order.completed_by_user_id,
        canceled_by_user_id=order.canceled_by_user_id,
        status=order.status,
        quantity=order.quantity,
        produced_quantity=order.produced_quantity,
        unit=order.unit,
        unit_cost=order.unit_cost,
        total_cost=order.total_cost,
        estimated_unit_cost=order.estimated_unit_cost,
        estimated_total_cost=order.estimated_total_cost,
        due_date=order.due_date,
        notes=order.notes,
        cancellation_reason=order.cancellation_reason,
        started_at=order.started_at,
        completed_at=order.completed_at,
        canceled_at=order.canceled_at,
        produced_at=order.produced_at,
        components=order.components,
    )


def get_order_or_404(db: Session, order_id: int) -> ProductionOrder:
    order = db.scalar(
        select(ProductionOrder)
        .options(
            selectinload(ProductionOrder.product),
            selectinload(ProductionOrder.components).selectinload(
                ProductionOrderComponent.component_product
            ),
        )
        .where(ProductionOrder.id == order_id)
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Ordem de producao nao encontrada.")
    return order


def _get_finished_product(db: Session, product_id: int) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto acabado nao encontrado.")
    if product.product_type not in {"produto", "produto_acabado"}:
        raise HTTPException(
            status_code=400,
            detail="Ordem de producao deve ser criada para produto ou produto acabado.",
        )
    return product


def _load_composition(db: Session, product_id: int) -> list[ProductCompositionItem]:
    items = list(
        db.scalars(
            select(ProductCompositionItem)
            .options(selectinload(ProductCompositionItem.component_product))
            .where(ProductCompositionItem.product_id == product_id)
            .order_by(ProductCompositionItem.id)
        ).all()
    )
    if not items:
        raise HTTPException(
            status_code=400,
            detail="Produto sem ficha tecnica. Cadastre a composicao antes de produzir.",
        )
    return items


def _calculate_components(
    db: Session,
    product_id: int,
    finished_quantity: Decimal,
    *,
    validate_stock: bool,
) -> tuple[list[tuple[ProductCompositionItem, Product, Decimal, Decimal | None, Decimal | None]], Decimal]:
    required: list[tuple[ProductCompositionItem, Product, Decimal, Decimal | None, Decimal | None]] = []
    total_cost = Decimal("0")
    for item in _load_composition(db, product_id):
        component = item.component_product
        try:
            quantity_per_finished = convert_quantity(item.quantity, item.unit, component.unit)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        quantity = quantity_per_finished * finished_quantity * (
            Decimal("1") + (item.waste_percent / Decimal("100"))
        )
        if validate_stock and component.stock_quantity < quantity:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Estoque insuficiente para {component.name}. "
                    f"Necessario: {quantity} {component.unit}. "
                    f"Disponivel: {component.stock_quantity} {component.unit}."
                ),
            )
        unit_cost = base_unit_cost(component)
        component_total = quantity * unit_cost if unit_cost is not None else None
        if component_total is not None:
            total_cost += component_total
        required.append((item, component, quantity, unit_cost, component_total))
    return required, total_cost


def _set_estimate(db: Session, order: ProductionOrder) -> None:
    _, estimated_total = _calculate_components(
        db,
        order.product_id,
        order.quantity,
        validate_stock=False,
    )
    order.estimated_total_cost = estimated_total
    order.estimated_unit_cost = estimated_total / order.quantity if order.quantity > 0 else None


def _complete_order(
    db: Session,
    order: ProductionOrder,
    user: User,
    produced_quantity: Decimal,
    notes: str | None,
) -> ProductionOrder:
    if order.status not in OPEN_STATUSES:
        raise HTTPException(status_code=400, detail="Apenas OP planejada ou em producao pode ser concluida.")
    if produced_quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantidade produzida deve ser maior que zero.")

    product = order.product
    required_components, total_cost = _calculate_components(
        db,
        product.id,
        produced_quantity,
        validate_stock=True,
    )

    order.status = "concluida"
    order.produced_quantity = produced_quantity
    order.completed_by_user_id = user.id
    order.started_at = order.started_at or now_utc()
    order.completed_at = now_utc()
    order.notes = "\n".join(part for part in [order.notes, notes] if part)

    quantity_before = product.stock_quantity
    finished_unit_cost, finished_total_cost = apply_stock_in(product, produced_quantity, total_cost)
    order.unit_cost = finished_unit_cost
    order.total_cost = finished_total_cost or total_cost
    upsert_product_batch(
        db,
        product,
        produced_quantity,
        batch_number=order.number,
        source_type="production",
        source_id=order.id,
        source_number=order.number,
        notes=f"Saldo produzido pela ordem {order.number}.",
    )

    db.add(
        StockMovement(
            product_id=product.id,
            user_id=user.id,
            movement_type="production_in",
            source_type="production",
            source_id=order.id,
            source_number=order.number,
            quantity_delta=produced_quantity,
            quantity_before=quantity_before,
            quantity_after=product.stock_quantity,
            unit=product.unit,
            unit_price=finished_unit_cost,
            total_value=finished_total_cost,
            reason="Conclusao de ordem de producao",
            notes=f"Entrada automatica da ordem {order.number}.",
        )
    )

    order.components.clear()
    db.flush()
    for item, component, quantity, _, _ in required_components:
        component_before = component.stock_quantity
        component_cost, component_total = apply_stock_out(component, quantity)
        apply_batch_out(
            db,
            component,
            quantity,
            source_type="production",
            source_id=order.id,
            source_number=order.number,
        )
        order.components.append(
            ProductionOrderComponent(
                component_product_id=component.id,
                component_name=component.name,
                quantity=quantity,
                unit=component.unit,
                waste_percent=item.waste_percent,
                unit_cost=component_cost,
                total_cost=component_total,
            )
        )
        db.add(
            StockMovement(
                product_id=component.id,
                user_id=user.id,
                movement_type="production_consumption",
                source_type="production",
                source_id=order.id,
                source_number=order.number,
                quantity_delta=-quantity,
                quantity_before=component_before,
                quantity_after=component.stock_quantity,
                unit=component.unit,
                unit_price=component_cost,
                total_value=component_total,
                reason="Consumo em producao",
                notes=f"Baixa automatica da ordem {order.number} para produzir {product.name}.",
            )
        )
    return order


@router.post("", response_model=ProductionOrderRead, status_code=status.HTTP_201_CREATED)
def create_production_order(
    order_in: ProductionOrderCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("production:create")),
) -> ProductionOrderRead:
    product = _get_finished_product(db, order_in.product_id)
    order = ProductionOrder(
        product_id=product.id,
        user_id=current_user.id,
        status="planejada",
        quantity=order_in.quantity,
        produced_quantity=Decimal("0"),
        unit=product.unit,
        due_date=order_in.due_date,
        notes=order_in.notes,
    )
    _set_estimate(db, order)
    db.add(order)
    db.flush()
    order.number = production_order_number(order.id)
    db.commit()
    return _read_order(get_order_or_404(db, order.id))


@router.get("/preview", response_model=ProductionOrderPreview)
def preview_production_order(
    product_id: int = Query(gt=0),
    quantity: Decimal = Query(gt=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("production:view", "production:create")),
) -> ProductionOrderPreview:
    product = _get_finished_product(db, product_id)
    required, total_cost = _calculate_components(
        db,
        product.id,
        quantity,
        validate_stock=False,
    )
    return ProductionOrderPreview(
        product_id=product.id,
        quantity=quantity,
        unit=product.unit,
        estimated_unit_cost=total_cost / quantity if quantity > 0 else None,
        estimated_total_cost=total_cost,
        components=[
            ProductionOrderComponentPreview(
                component_product_id=component.id,
                component_name=component.name,
                requested_quantity=item.quantity,
                requested_unit=item.unit,
                required_quantity=required_quantity,
                stock_quantity=component.stock_quantity,
                unit=component.unit,
                waste_percent=item.waste_percent,
                unit_cost=unit_cost,
                total_cost=component_total,
                enough_stock=component.stock_quantity >= required_quantity,
            )
            for item, component, required_quantity, unit_cost, component_total in required
        ],
    )


@router.post("/{order_id}/start", response_model=ProductionOrderRead)
def start_production_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("production:create")),
) -> ProductionOrderRead:
    order = get_order_or_404(db, order_id)
    if order.status != "planejada":
        raise HTTPException(status_code=400, detail="Apenas OP planejada pode entrar em producao.")
    order.status = "em_producao"
    order.started_at = now_utc()
    db.commit()
    return _read_order(get_order_or_404(db, order.id))


@router.post("/{order_id}/complete", response_model=ProductionOrderRead)
def complete_production_order(
    order_id: int,
    complete_in: ProductionOrderComplete,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("production:create")),
) -> ProductionOrderRead:
    order = get_order_or_404(db, order_id)
    produced_quantity = complete_in.produced_quantity or order.quantity
    _complete_order(db, order, current_user, produced_quantity, complete_in.notes)
    db.commit()
    return _read_order(get_order_or_404(db, order.id))


@router.post("/{order_id}/cancel", response_model=ProductionOrderRead)
def cancel_production_order(
    order_id: int,
    cancel_in: ProductionOrderCancel,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("production:create")),
) -> ProductionOrderRead:
    order = get_order_or_404(db, order_id)
    if order.status == "cancelada":
        raise HTTPException(status_code=400, detail="OP ja esta cancelada.")

    if order.status == "concluida":
        product = order.product
        if product.stock_quantity < order.produced_quantity:
            raise HTTPException(
                status_code=400,
                detail="Nao e possivel cancelar: produto acabado ja saiu do estoque.",
            )
        product_before = product.stock_quantity
        product_unit_cost, product_total = apply_stock_out(product, order.produced_quantity)
        apply_batch_out(
            db,
            product,
            order.produced_quantity,
            source_type="production_cancel",
            source_id=order.id,
            source_number=order.number,
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=current_user.id,
                movement_type="production_cancel_out",
                source_type="production",
                source_id=order.id,
                source_number=order.number,
                quantity_delta=-order.produced_quantity,
                quantity_before=product_before,
                quantity_after=product.stock_quantity,
                unit=product.unit,
                unit_price=product_unit_cost,
                total_value=product_total,
                reason="Cancelamento de OP concluida",
                notes=cancel_in.reason,
            )
        )

        for component_snapshot in order.components:
            component = component_snapshot.component_product or db.get(Product, component_snapshot.component_product_id)
            if component is None:
                continue
            before = component.stock_quantity
            component_unit_cost, component_total = apply_stock_in(
                component,
                component_snapshot.quantity,
                component_snapshot.total_cost,
            )
            return_to_batch(
                db,
                component,
                component_snapshot.quantity,
                source_type="production_cancel",
                source_id=order.id,
                source_number=order.number,
            )
            db.add(
                StockMovement(
                    product_id=component.id,
                    user_id=current_user.id,
                    movement_type="production_cancel_return",
                    source_type="production",
                    source_id=order.id,
                    source_number=order.number,
                    quantity_delta=component_snapshot.quantity,
                    quantity_before=before,
                    quantity_after=component.stock_quantity,
                    unit=component.unit,
                    unit_price=component_unit_cost,
                    total_value=component_total,
                    reason="Estorno de consumo de producao",
                    notes=cancel_in.reason,
                )
            )

    order.status = "cancelada"
    order.canceled_by_user_id = current_user.id
    order.canceled_at = now_utc()
    order.cancellation_reason = cancel_in.reason
    db.commit()
    return _read_order(get_order_or_404(db, order.id))


@router.get("", response_model=list[ProductionOrderRead])
def list_production_orders(
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("production:view", "production:create")),
) -> list[ProductionOrderRead]:
    orders = list(
        db.scalars(
            select(ProductionOrder)
            .options(
                selectinload(ProductionOrder.product),
                selectinload(ProductionOrder.components),
            )
            .order_by(ProductionOrder.id.desc())
            .limit(limit)
        ).all()
    )
    return [_read_order(order) for order in orders]


@router.get("/{order_id}", response_model=ProductionOrderRead)
def get_production_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("production:view", "production:create")),
) -> ProductionOrderRead:
    return _read_order(get_order_or_404(db, order_id))

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.pedeon.application.inventory_service import PedeOnInventoryService
from app.modules.pedeon.application.order_schemas import OrderDetailRead
from app.modules.pedeon.application.order_service import (
    PedeOnOrderService,
    PedeOnPublicOrderService,
)
from app.modules.pedeon.application.public_catalog_service import (
    MONEY,
    PedeOnPublicCatalogService,
)
from app.modules.pedeon.application.staff_schemas import EdgeStaffOrderCreate
from app.modules.pedeon.domain.lifecycle import OrderStatus, PaymentStatus
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOrder,
    PedeOnOrderItem,
    PedeOnOrderItemModifier,
    PedeOnStore,
)


class PedeOnStaffOrderService:
    def __init__(self, db: Session):
        self.db = db

    def create(
        self,
        store: PedeOnStore,
        payload: EdgeStaffOrderCreate,
        terminal_id: int,
    ) -> OrderDetailRead:
        existing = self.db.scalar(
            select(PedeOnOrder).where(
                PedeOnOrder.store_id == store.id,
                PedeOnOrder.idempotency_key == payload.idempotency_key,
            )
        )
        if existing is not None:
            return PedeOnOrderService(self.db).detail(existing.id)

        lines = PedeOnPublicCatalogService.resolve_cart(
            self.db,
            store,
            payload.items,
            channel=payload.source_channel,
        )
        subtotal = sum((line.total for line in lines), Decimal("0")).quantize(MONEY)
        order = PedeOnOrder(
            idempotency_key=payload.idempotency_key,
            store_id=store.id,
            source_channel=payload.source_channel,
            source_metadata={
                "entrypoint": "edge_staff",
                "table_label": payload.table_label,
                "command_label": payload.command_label,
                "terminal_id": terminal_id,
                "waiter_email": payload.waiter_email,
                "waiter_name": payload.waiter_name,
            },
            status=OrderStatus.AWAITING_ACCEPTANCE,
            payment_status=PaymentStatus.PENDING,
            fulfillment_type="dine_in",
            customer_name=payload.customer_name.strip(),
            customer_phone="local",
            subtotal_amount=subtotal,
            total_amount=subtotal,
            customer_notes=(payload.customer_notes or "").strip() or None,
        )
        self.db.add(order)
        self.db.flush()
        order.display_number = f"PED-{order.id:06d}"

        demands: dict[int, dict[int, Decimal]] = {}
        for sort_order, line in enumerate(lines):
            item = PedeOnOrderItem(
                order_id=order.id,
                product_id=line.product.id,
                publication_id=line.publication.id if line.publication else None,
                product_code=line.product.internal_code,
                barcode=line.product.barcode,
                description=(
                    line.publication.display_name
                    if line.publication is not None and line.publication.display_name
                    else line.product.name
                ),
                quantity=line.request.quantity,
                unit=line.product.unit,
                unit_price=line.base_unit_price,
                modifiers_amount=line.modifiers_unit_amount,
                total_amount=line.total,
                customer_notes=(line.request.customer_notes or "").strip() or None,
                fiscal_snapshot={
                    "ncm": line.product.ncm,
                    "cest": line.product.cest,
                    "cfop_sale": line.product.cfop_sale,
                    "origin": line.product.origin,
                    "cst": line.product.cst,
                    "csosn": line.product.csosn,
                },
                sort_order=sort_order,
            )
            self.db.add(item)
            self.db.flush()
            if line.product.product_type != "servico":
                demands.setdefault(item.id, {})[line.product.id] = Decimal(line.request.quantity)
            for sequence, modifier in enumerate(line.modifiers):
                self.db.add(PedeOnOrderItemModifier(
                    order_item_id=item.id,
                    group_id=modifier.group.id,
                    option_id=modifier.option.id,
                    group_name=modifier.group.name,
                    option_name=modifier.option.name,
                    quantity=modifier.quantity,
                    unit_price=modifier.unit_price,
                    total_amount=modifier.total,
                    sequence=sequence,
                ))
                if modifier.option.product_id is not None:
                    product_demands = demands.setdefault(item.id, {})
                    product_demands[modifier.option.product_id] = product_demands.get(
                        modifier.option.product_id, Decimal("0")
                    ) + Decimal(modifier.quantity) * Decimal(line.request.quantity)

        PedeOnInventoryService(self.db).reserve(order, demands)
        PedeOnPublicOrderService._events(self.db, order)
        engine = PedeOnOrderService(self.db)
        engine._accept_and_start_preparation(
            order, actor_type="terminal", actor_id=str(terminal_id)
        )
        self.db.commit()
        return engine.detail(order.id)

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.product import Product
from app.models.stock_movement import StockMovement
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOrder,
    PedeOnOrderEvent,
    PedeOnOrderItem,
    PedeOnOutboxEvent,
    PedeOnStore,
    PedeOnStockReservation,
)
from app.services.product_batches import apply_batch_out
from app.services.product_costs import apply_stock_out


ACTIVE_RESERVATION_STATUSES = ("temporary", "committed")


def inventory_policy_for_store(db: Session, store_id: int) -> str:
    store = db.get(PedeOnStore, store_id)
    if store is None:
        return "strict_block"
    configured = (store.settings or {}).get("inventory_policy")
    if configured in {"warn_allow", "strict_block", "untracked"}:
        return configured
    return "warn_allow" if store.experience_mode == "food_service" else "strict_block"


class PedeOnInventoryService:
    """Reserva e consome estoque do PedeOn com proteção concorrente.

    O saldo físico só é alterado quando o pedido é concluído. Até lá, a
    disponibilidade é o saldo físico menos as reservas ativas. Os produtos são
    bloqueados sempre na ordem do ID para reduzir a possibilidade de deadlock.
    """

    def __init__(self, db: Session):
        self.db = db

    def release_expired(self, *, now: datetime | None = None) -> int:
        now = now or datetime.now(timezone.utc)
        reservations = self.db.scalars(
            select(PedeOnStockReservation)
            .where(
                PedeOnStockReservation.status == "temporary",
                PedeOnStockReservation.expires_at.is_not(None),
                PedeOnStockReservation.expires_at <= now,
            )
            .with_for_update()
        ).all()
        if not reservations:
            return 0
        order_ids: set[int] = set()
        for reservation in reservations:
            reservation.status = "released"
            reservation.released_at = now
            reservation.release_reason = "reservation_expired"
            order_ids.add(reservation.order_id)
        for order_id in order_ids:
            order = self.db.get(PedeOnOrder, order_id)
            if order is not None and order.status in {
                "awaiting_payment",
                "awaiting_acceptance",
            }:
                previous_status = order.status
                order.status = "cancelled"
                order.cancelled_at = now
                order.updated_at = now
                order.version += 1
                event_key = str(uuid4())
                payload = {
                    "status": "cancelled",
                    "reason": "reservation_expired",
                    "source_channel": order.source_channel,
                    "external_order_id": order.external_order_id,
                }
                self.db.add(
                    PedeOnOrderEvent(
                        event_key=event_key,
                        order_id=order.id,
                        event_type="pedeon.order.status.changed",
                        from_status=previous_status,
                        to_status="cancelled",
                        order_version=order.version,
                        actor_type="system",
                        actor_id="inventory-reservation-expiry",
                        payload=payload,
                    )
                )
                self.db.add(
                    PedeOnOutboxEvent(
                        event_key=f"{event_key}:outbox",
                        aggregate_type="order",
                        aggregate_id=order.public_id,
                        event_type="pedeon.order.status.changed",
                        payload=payload,
                    )
                )
        return len(reservations)

    def reserve(
        self,
        order: PedeOnOrder,
        demands_by_item: dict[int, dict[int, Decimal]],
    ) -> None:
        policy = inventory_policy_for_store(self.db, order.store_id)
        if policy == "untracked":
            return
        normalized: dict[int, dict[int, Decimal]] = {}
        total_by_product: dict[int, Decimal] = defaultdict(lambda: Decimal("0"))
        for order_item_id, product_demands in demands_by_item.items():
            for product_id, raw_quantity in product_demands.items():
                quantity = Decimal(raw_quantity)
                if quantity <= 0:
                    continue
                normalized.setdefault(order_item_id, {})[product_id] = (
                    normalized.setdefault(order_item_id, {}).get(
                        product_id, Decimal("0")
                    )
                    + quantity
                )
                total_by_product[product_id] += quantity
        if not total_by_product:
            return

        now = datetime.now(timezone.utc)
        self.release_expired(now=now)
        product_ids = sorted(total_by_product)
        products = {
            product.id: product
            for product in self.db.scalars(
                select(Product)
                .where(Product.id.in_(product_ids))
                .order_by(Product.id)
                .with_for_update()
            ).all()
        }
        if set(product_ids) != set(products):
            raise ValueError("Um item do pedido não existe mais no estoque.")

        reserved_rows = self.db.execute(
            select(
                PedeOnStockReservation.product_id,
                func.coalesce(func.sum(PedeOnStockReservation.quantity), 0),
            )
            .where(
                PedeOnStockReservation.product_id.in_(product_ids),
                PedeOnStockReservation.status.in_(ACTIVE_RESERVATION_STATUSES),
            )
            .group_by(PedeOnStockReservation.product_id)
        ).all()
        reserved_by_product = {
            product_id: Decimal(quantity) for product_id, quantity in reserved_rows
        }
        shortages: list[dict[str, str | int]] = []
        for product_id in product_ids:
            product = products[product_id]
            if not product.active or product.product_type == "servico":
                if product.product_type == "servico":
                    continue
                raise ValueError(f"{product.name} não está disponível no momento.")
            available = Decimal(product.stock_quantity) - reserved_by_product.get(
                product_id, Decimal("0")
            )
            demanded = total_by_product[product_id]
            if demanded > available:
                if policy == "strict_block":
                    raise ValueError(
                        f"Estoque insuficiente para {product.name}. "
                        f"Disponível: {available} {product.unit}."
                    )
                shortages.append(
                    {
                        "product_id": product.id,
                        "product_name": product.name,
                        "required": str(demanded),
                        "available": str(available),
                        "unit": product.unit,
                    }
                )

        metadata = dict(order.source_metadata or {})
        metadata["inventory_policy"] = policy
        if shortages:
            metadata["inventory_warnings"] = shortages
        else:
            metadata.pop("inventory_warnings", None)
        order.source_metadata = metadata

        expires_at = now + timedelta(
            minutes=max(1, get_settings().pedeon_stock_reservation_minutes)
        )
        order.expires_at = expires_at
        for order_item_id, product_demands in normalized.items():
            for product_id, quantity in product_demands.items():
                product = products[product_id]
                if product.product_type == "servico":
                    continue
                self.db.add(
                    PedeOnStockReservation(
                        order_id=order.id,
                        order_item_id=order_item_id,
                        product_id=product_id,
                        quantity=quantity,
                        status="temporary",
                        reservation_type="checkout",
                        expires_at=expires_at,
                    )
                )

    def commit(self, order_id: int) -> int:
        reservations = self._locked_active(order_id)
        for reservation in reservations:
            reservation.status = "committed"
            reservation.expires_at = None
        order = self.db.get(PedeOnOrder, order_id)
        if order is not None:
            order.expires_at = None
        return len(reservations)

    def release(self, order_id: int, reason: str) -> int:
        now = datetime.now(timezone.utc)
        reservations = self._locked_active(order_id)
        for reservation in reservations:
            reservation.status = "released"
            reservation.released_at = now
            reservation.release_reason = reason[:120]
        return len(reservations)

    def consume(self, order: PedeOnOrder) -> int:
        reservations = self._locked_active(order.id)
        if not reservations:
            already_consumed = self.db.scalar(
                select(func.count())
                .select_from(PedeOnStockReservation)
                .where(
                    PedeOnStockReservation.order_id == order.id,
                    PedeOnStockReservation.status == "consumed",
                )
            )
            if already_consumed:
                return 0
            # Pedidos compostos apenas por serviços ou pedidos antigos, criados
            # antes da ativação das reservas, não têm linhas de estoque.
            return 0

        quantity_by_product: dict[int, Decimal] = defaultdict(lambda: Decimal("0"))
        for reservation in reservations:
            quantity_by_product[reservation.product_id] += Decimal(reservation.quantity)
        product_ids = sorted(quantity_by_product)
        products = {
            product.id: product
            for product in self.db.scalars(
                select(Product)
                .where(Product.id.in_(product_ids))
                .order_by(Product.id)
                .with_for_update()
            ).all()
        }
        if set(products) != set(product_ids):
            raise ValueError("Um produto reservado não existe mais.")

        now = datetime.now(timezone.utc)
        for product_id in product_ids:
            product = products[product_id]
            quantity = quantity_by_product[product_id]
            before = Decimal(product.stock_quantity)
            unit_cost, total_cost = apply_stock_out(product, quantity)
            apply_batch_out(
                self.db,
                product,
                quantity,
                source_type="pedeon_order",
                source_id=order.id,
                source_number=order.display_number,
            )
            self.db.add(
                StockMovement(
                    product_id=product.id,
                    movement_type="pedeon_order_out",
                    source_type="pedeon_order",
                    source_id=order.id,
                    source_number=order.display_number,
                    quantity_delta=-quantity,
                    quantity_before=before,
                    quantity_after=product.stock_quantity,
                    unit=product.unit,
                    unit_price=unit_cost,
                    total_value=total_cost,
                    reason="Pedido PedeOn concluído",
                    notes=(
                        f"Consumo idempotente da reserva do pedido "
                        f"{order.display_number}."
                    ),
                )
            )
        for reservation in reservations:
            reservation.status = "consumed"
            reservation.consumed_at = now
            reservation.expires_at = None
        return len(reservations)

    def _locked_active(self, order_id: int) -> list[PedeOnStockReservation]:
        return list(
            self.db.scalars(
                select(PedeOnStockReservation)
                .where(
                    PedeOnStockReservation.order_id == order_id,
                    PedeOnStockReservation.status.in_(ACTIVE_RESERVATION_STATUSES),
                )
                .order_by(PedeOnStockReservation.product_id, PedeOnStockReservation.id)
                .with_for_update()
            ).all()
        )

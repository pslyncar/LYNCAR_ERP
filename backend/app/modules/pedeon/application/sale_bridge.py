from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.sale import Sale, SaleItem, SalePayment
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOrder,
    PedeOnOrderItem,
    PedeOnPaymentTransaction,
)
from app.modules.pedeon.domain.lifecycle import PaymentStatus

MONEY = Decimal("0.01")
PAYMENT_METHODS = {
    "infinitepay_pix": "pix",
    "manual_pix": "pix",
    "cash_on_delivery": "dinheiro",
    "card_on_delivery": "credito",
    "credit_card_on_delivery": "credito",
    "debit_card_on_delivery": "debito",
    "dinheiro": "dinheiro",
    "pix": "pix",
    "debito": "debito",
    "credito": "credito",
}


class PedeOnSaleBridge:
    """Convergência idempotente dos canais PedeOn para a venda do ERP."""

    def __init__(self, db: Session):
        self.db = db

    def ensure_sale(
        self,
        order: PedeOnOrder,
        *,
        actor_type: str,
        actor_id: str,
    ) -> Sale:
        if order.sale_id is not None:
            sale = self.db.get(Sale, order.sale_id)
            if sale is None:
                raise RuntimeError("Venda vinculada ao pedido não foi encontrada.")
            return sale
        existing = self.db.scalar(
            select(Sale).where(Sale.offline_client_id == f"pedeon:{order.public_id}")
        )
        if existing is not None:
            order.sale_id = existing.id
            return existing

        transaction = self.db.scalar(
            select(PedeOnPaymentTransaction)
            .where(PedeOnPaymentTransaction.order_id == order.id)
            .order_by(PedeOnPaymentTransaction.id.desc())
        )
        pay_on_delivery = {
            "cash_on_delivery",
            "card_on_delivery",
            "credit_card_on_delivery",
            "debit_card_on_delivery",
        }
        if transaction is None:
            raise ValueError("Pedido sem pagamento definido não pode ser concluído.")
        if transaction.status != PaymentStatus.CONFIRMED:
            if transaction.method not in pay_on_delivery:
                raise ValueError("Confirme o pagamento antes de concluir o pedido.")
            transaction.status = PaymentStatus.CONFIRMED
            transaction.confirmed_at = order.completed_at
            order.payment_status = PaymentStatus.CONFIRMED
        metadata = dict(transaction.metadata_payload or {}) if transaction else {}
        total = Decimal(order.total_amount).quantize(MONEY, rounding=ROUND_HALF_UP)
        tendered = Decimal(str(metadata.get("amount_tendered", total))).quantize(
            MONEY, rounding=ROUND_HALF_UP
        )
        method = PAYMENT_METHODS.get(transaction.method if transaction else "", "outro")
        operator = str(metadata.get("operator_name") or f"{actor_type}:{actor_id}")
        terminal_id = metadata.get("terminal_id")
        cash_session_id = metadata.get("cash_session_id")
        cash_register_number = metadata.get("cash_register_number")
        sale = Sale(
            source="pedeon",
            cash_session_id=int(cash_session_id) if cash_session_id else None,
            cash_register_number=(
                str(cash_register_number) if cash_register_number else None
            ),
            client_id=order.client_id,
            status="finalizada",
            subtotal_amount=order.subtotal_amount,
            discount_amount=order.discount_amount,
            total_amount=total,
            amount_paid=max(total, tendered),
            change_amount=max(Decimal("0"), tendered - total),
            consumer_cpf=order.customer_document,
            offline_client_id=f"pedeon:{order.public_id}",
            notes=(
                f"Pedido {order.display_number or order.public_id} | "
                f"Canal: {order.source_channel} | Operador: {operator}"
                + (f" | Terminal: {terminal_id}" if terminal_id else "")
            ),
            # No salão o cliente pode pagar antes de a cozinha finalizar. A
            # venda contábil deve registrar o instante do recebimento, sem
            # antecipar o status operacional do pedido.
            sold_at=order.completed_at or datetime.now(timezone.utc),
        )
        items = self.db.scalars(
            select(PedeOnOrderItem)
            .where(PedeOnOrderItem.order_id == order.id)
            .order_by(PedeOnOrderItem.sort_order, PedeOnOrderItem.id)
        ).all()
        for item in items:
            unit_total = (
                Decimal(item.total_amount) / Decimal(item.quantity)
            ).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
            sale.items.append(
                SaleItem(
                    product_id=item.product_id,
                    barcode=item.barcode,
                    description=item.description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=unit_total,
                    discount_amount=item.discount_amount,
                    total_price=item.total_amount,
                )
            )
        sale.payments.append(
            SalePayment(
                method=method,
                amount=max(total, tendered),
                authorization_code=(
                    transaction.manual_reference if transaction is not None else None
                ),
                notes=f"Pagamento originado no PedeOn ({order.source_channel}).",
            )
        )
        self.db.add(sale)
        self.db.flush()
        sale.number = f"V{sale.id}"
        order.sale_id = sale.id
        return sale

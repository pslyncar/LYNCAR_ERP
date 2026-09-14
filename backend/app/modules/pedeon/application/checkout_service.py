from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.sale import Sale
from app.models.pdv_cash_session import PdvCashSession
from app.modules.pedeon.application.inventory_service import PedeOnInventoryService
from app.modules.pedeon.application.order_service import PedeOnOrderService
from app.modules.pedeon.application.sale_bridge import PedeOnSaleBridge
from app.modules.pedeon.application.staff_schemas import EdgeOrderCheckout
from app.modules.pedeon.domain.lifecycle import OrderStatus, PaymentStatus
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOrder,
    PedeOnPaymentTransaction,
    PedeOnStore,
)

MONEY = Decimal("0.01")


class PedeOnCheckoutService:
    """Recebe uma conta PedeOn sem encerrar indevidamente o preparo.

    O recebimento confirma o pagamento, consolida a venda do ERP e mantém a
    reserva de estoque. Pedidos ainda em preparo continuam visíveis para a
    cozinha; o consumo físico acontece somente quando o preparo é concluído.
    """

    def __init__(self, db: Session):
        self.db = db

    def checkout(
        self,
        store: PedeOnStore,
        order_public_id: str,
        payload: EdgeOrderCheckout,
    ) -> dict:
        order = self.db.scalar(
            select(PedeOnOrder)
            .where(
                PedeOnOrder.store_id == store.id,
                PedeOnOrder.public_id == order_public_id,
            )
            .with_for_update()
        )
        if order is None:
            raise LookupError("Pedido não encontrado.")
        if order.sale_id is not None:
            sale = self.db.get(Sale, order.sale_id)
            return self._result(order, sale)
        current_status = OrderStatus(order.status)
        if current_status not in {
            OrderStatus.ACCEPTED,
            OrderStatus.IN_PREPARATION,
            OrderStatus.READY,
        }:
            raise ValueError(
                "Este pedido ainda não está disponível para recebimento no caixa."
            )

        total = Decimal(order.total_amount).quantize(MONEY, rounding=ROUND_HALF_UP)
        paid = Decimal(payload.amount_paid).quantize(MONEY, rounding=ROUND_HALF_UP)
        if paid < total:
            raise ValueError("Pagamento menor que o total do pedido.")
        if payload.payment_method != "dinheiro" and paid != total:
            raise ValueError("Pagamento em cartão ou Pix deve ser igual ao total.")

        cash_session = self.db.get(PdvCashSession, payload.cash_session_id)
        session_operator_mismatch = (
            cash_session is None
            or cash_session.status != "open"
            or cash_session.operator_name != payload.operator_name
            or cash_session.cash_register_number != payload.cash_register_number
            or (
                payload.operator_type == "pedeon_operator"
                and cash_session.operator_id != payload.operator_id
            )
        )
        if session_operator_mismatch:
            raise ValueError("Sessão de caixa inválida, encerrada ou de outro operador.")

        transaction = self.db.scalar(
            select(PedeOnPaymentTransaction).where(
                PedeOnPaymentTransaction.idempotency_key == payload.idempotency_key
            )
        )
        now = datetime.now(timezone.utc)
        if transaction is None:
            transaction = PedeOnPaymentTransaction(
                order_id=order.id,
                idempotency_key=payload.idempotency_key,
                method=payload.payment_method,
                provider="local_terminal",
                status=PaymentStatus.CONFIRMED,
                amount=total,
                manual_reference=payload.authorization_code,
                metadata_payload={
                    "terminal_id": payload.terminal_id,
                    "operator_name": payload.operator_name,
                    "operator_id": payload.operator_id,
                    "amount_tendered": str(paid),
                    "cash_session_id": cash_session.id,
                    "cash_register_number": cash_session.cash_register_number,
                    "cash_session_local_key": payload.cash_session_local_key,
                },
                confirmed_at=now,
            )
            self.db.add(transaction)
            # A sessão do ERP desabilita autoflush. A ponte de venda consulta a
            # transação de pagamento durante a mudança para ``completed``;
            # portanto ela precisa existir no banco antes dessa consulta.
            self.db.flush()
        elif transaction.order_id != order.id:
            raise ValueError("Chave de recebimento já utilizada por outro pedido.")

        order.payment_status = PaymentStatus.CONFIRMED
        PedeOnInventoryService(self.db).commit(order.id)
        PedeOnSaleBridge(self.db).ensure_sale(
            order,
            actor_type="terminal",
            actor_id=str(payload.terminal_id),
        )
        # Se não há mais preparo pendente, o pedido pode ser concluído agora.
        # Caso contrário, ele permanece na cozinha até ficar pronto.
        if current_status == OrderStatus.READY:
            PedeOnOrderService(self.db)._apply_transition(
                order,
                OrderStatus.COMPLETED,
                actor_type="terminal",
                actor_id=str(payload.terminal_id),
            )
        self.db.commit()
        sale = self.db.get(Sale, order.sale_id)
        return self._result(order, sale)

    @staticmethod
    def _result(order: PedeOnOrder, sale: Sale | None) -> dict:
        if sale is None:
            raise RuntimeError("Venda vinculada ao pedido não foi encontrada.")
        return {
            "order_id": order.public_id,
            "order_status": order.status,
            "sale_id": sale.id,
            "sale_number": sale.number,
            "total_amount": str(sale.total_amount),
            "amount_paid": str(sale.amount_paid),
            "change_amount": str(sale.change_amount),
        }

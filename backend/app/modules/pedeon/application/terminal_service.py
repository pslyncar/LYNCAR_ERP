from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.pdv_terminal import PdvTerminal
from app.modules.pedeon.application.order_schemas import (
    OrderDetailRead,
    TerminalFeedEventRead,
    TerminalFeedRead,
    TerminalPrintJobRead,
)
from app.modules.pedeon.application.order_service import PedeOnOrderService
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOrder,
    PedeOnOutboxEvent,
    PedeOnPrintJob,
    PedeOnTerminalPermission,
)


class PedeOnTerminalService:
    def __init__(self, db: Session):
        self.db = db

    def feed(self, terminal_key: str, after: int, limit: int) -> TerminalFeedRead:
        terminal, permission = self._authorized(terminal_key, "view")
        rows = self.db.execute(
            select(PedeOnOutboxEvent, PedeOnOrder)
            .join(
                PedeOnOrder,
                PedeOnOrder.public_id == PedeOnOutboxEvent.aggregate_id,
            )
            .where(
                PedeOnOutboxEvent.id > after,
                PedeOnOutboxEvent.aggregate_type == "order",
                PedeOnOrder.store_id == permission.store_id,
            )
            .order_by(PedeOnOutboxEvent.id)
            .limit(limit + 1)
        ).all()
        visible = rows[:limit]
        next_cursor = visible[-1][0].id if visible else after
        now = datetime.now(timezone.utc)
        permission.last_seen_at = now
        terminal.last_seen_at = now
        terminal.updated_at = now
        self.db.commit()
        return TerminalFeedRead(
            terminal_id=terminal.id,
            next_cursor=next_cursor,
            has_more=len(rows) > limit,
            events=[
                TerminalFeedEventRead(
                    cursor=event.id,
                    event_key=event.event_key,
                    event_type=event.event_type,
                    order_id=order.public_id,
                    payload={
                        **(event.payload or {}),
                        "display_number": order.display_number,
                        "status": order.status,
                        "payment_status": order.payment_status,
                        "source_channel": order.source_channel,
                        "fulfillment_type": order.fulfillment_type,
                    },
                    created_at=event.created_at,
                )
                for event, order in visible
            ],
        )

    def order_detail(self, terminal_key: str, public_id: str) -> OrderDetailRead:
        _, permission = self._authorized(terminal_key, "view")
        order = self.db.scalar(
            select(PedeOnOrder).where(
                PedeOnOrder.public_id == public_id,
                PedeOnOrder.store_id == permission.store_id,
            )
        )
        if order is None:
            raise LookupError("Pedido não encontrado para este terminal.")
        return PedeOnOrderService(self.db).detail(order.id)

    def transition(
        self, terminal_key: str, public_id: str, target_status: str
    ) -> OrderDetailRead:
        capability = {
            "accepted": "accept",
            "in_preparation": "prepare",
            "ready": "prepare",
            "out_for_delivery": "dispatch",
            "completed": "dispatch",
            "cancelled": "cancel",
        }.get(target_status)
        if capability is None:
            raise ValueError("Estado não permitido pelo terminal.")
        terminal, permission = self._authorized(terminal_key, capability)
        order = self.db.scalar(
            select(PedeOnOrder).where(
                PedeOnOrder.public_id == public_id,
                PedeOnOrder.store_id == permission.store_id,
            )
        )
        if order is None:
            raise LookupError("Pedido não encontrado para este terminal.")
        return PedeOnOrderService(self.db).transition(
            order.id,
            target_status,
            terminal.id,
            actor_type="terminal",
        )

    def claim_print_jobs(
        self, terminal_key: str, limit: int
    ) -> list[TerminalPrintJobRead]:
        terminal, permission = self._authorized(terminal_key, "print")
        now = datetime.now(timezone.utc)
        stale_claim = now - timedelta(minutes=2)
        query = (
            select(PedeOnPrintJob)
            .join(PedeOnOrder, PedeOnOrder.id == PedeOnPrintJob.order_id)
            .where(
                PedeOnOrder.store_id == permission.store_id,
                PedeOnPrintJob.available_at <= now,
                or_(
                    PedeOnPrintJob.status == "pending",
                    (
                        (PedeOnPrintJob.status == "claimed")
                        & (PedeOnPrintJob.claimed_at <= stale_claim)
                    ),
                ),
                or_(
                    PedeOnPrintJob.target_terminal_id.is_(None),
                    PedeOnPrintJob.target_terminal_id == terminal.id,
                ),
            )
            .order_by(PedeOnPrintJob.available_at, PedeOnPrintJob.id)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        if permission.station_ids:
            query = query.where(
                PedeOnPrintJob.station_id.in_(permission.station_ids)
            )
        jobs = list(self.db.scalars(query).all())
        for job in jobs:
            job.status = "claimed"
            job.target_terminal_id = terminal.id
            job.claimed_at = now
            job.attempts += 1
        permission.last_seen_at = now
        terminal.last_seen_at = now
        terminal.updated_at = now
        self.db.commit()
        return [
            TerminalPrintJobRead(
                id=job.id,
                job_key=job.job_key,
                document_type=job.document_type,
                payload=job.payload or {},
                attempts=job.attempts,
                created_at=job.created_at,
            )
            for job in jobs
        ]

    def finish_print_job(
        self,
        terminal_key: str,
        job_id: int,
        status: str,
        error: str | None,
    ) -> TerminalPrintJobRead:
        terminal, permission = self._authorized(terminal_key, "print")
        job = self.db.scalar(
            select(PedeOnPrintJob)
            .join(PedeOnOrder, PedeOnOrder.id == PedeOnPrintJob.order_id)
            .where(
                PedeOnPrintJob.id == job_id,
                PedeOnOrder.store_id == permission.store_id,
                PedeOnPrintJob.target_terminal_id == terminal.id,
            )
            .with_for_update()
        )
        if job is None:
            raise LookupError("Trabalho de impressão não encontrado.")
        now = datetime.now(timezone.utc)
        if status == "printed":
            job.status = "printed"
            job.printed_at = now
            job.last_error = None
        elif status == "failed":
            job.status = "pending"
            job.available_at = now + timedelta(
                seconds=min(60, 2 ** min(job.attempts, 6))
            )
            job.claimed_at = None
            job.target_terminal_id = None
            job.last_error = (error or "Falha não detalhada.")[:1000]
        else:
            raise ValueError("Resultado de impressão inválido.")
        self.db.commit()
        return TerminalPrintJobRead(
            id=job.id,
            job_key=job.job_key,
            document_type=job.document_type,
            payload=job.payload or {},
            attempts=job.attempts,
            created_at=job.created_at,
        )

    def _authorized(
        self, terminal_key: str, capability: str
    ) -> tuple[PdvTerminal, PedeOnTerminalPermission]:
        cleaned = terminal_key.strip()
        if not cleaned:
            raise PermissionError("Terminal não identificado.")
        terminal = self.db.scalar(
            select(PdvTerminal).where(
                PdvTerminal.terminal_key == cleaned,
                PdvTerminal.active.is_(True),
                PdvTerminal.activation_status != "blocked",
            )
        )
        if terminal is None:
            raise PermissionError("Terminal não autorizado.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.pdv_terminal_id == terminal.id,
                PedeOnTerminalPermission.enabled.is_(True),
            )
        )
        if permission is None or capability not in (permission.capabilities or []):
            raise PermissionError("Este terminal não tem acesso aos pedidos PedeOn.")
        return terminal, permission

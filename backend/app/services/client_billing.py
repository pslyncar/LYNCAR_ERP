import calendar
from datetime import datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.client import Client
from app.models.receivable import Receivable

MONTHLY_RECEIVABLE_NOTE_PREFIX = "Mensalidade gerada automaticamente pelo cadastro do cliente."


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


def ensure_monthly_contract_is_valid(client: Client) -> None:
    if client.contract_type != "mensal":
        return
    if client.monthly_fee <= Decimal("0"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Informe o valor mensal do contrato.",
        )
    if client.monthly_due_day is None or not 1 <= client.monthly_due_day <= 31:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Informe o dia de vencimento da mensalidade.",
        )


def sync_current_month_receivable(db: Session, client: Client) -> None:
    if client.contract_type != "mensal" or not client.active:
        return
    ensure_monthly_contract_is_valid(client)
    now = datetime.utcnow()
    period_start, period_end = _monthly_period_bounds(now)
    due_date = _monthly_due_date(now.year, now.month, client.monthly_due_day or 1)
    description = f"Mensalidade {client.name} - {now.month:02d}/{now.year}"
    marker = f"{MONTHLY_RECEIVABLE_NOTE_PREFIX} Competencia {now.year}-{now.month:02d}."

    receivable = db.scalar(
        select(Receivable).where(
            Receivable.client_id == client.id,
            Receivable.due_date >= period_start,
            Receivable.due_date < period_end,
            Receivable.notes.like(f"{MONTHLY_RECEIVABLE_NOTE_PREFIX}%"),
        )
    )
    if receivable is None:
        receivable = Receivable(
            client_id=client.id,
            description=description,
            original_amount=client.monthly_fee,
            paid_amount=Decimal("0"),
            balance_amount=client.monthly_fee,
            status="open",
            due_date=due_date,
            notes=marker,
        )
        db.add(receivable)
        db.flush()
        receivable.number = receivable_number(receivable.id)
        return

    if receivable.status == "paid":
        return
    receivable.description = description
    receivable.due_date = due_date
    receivable.original_amount = client.monthly_fee
    receivable.balance_amount = max(
        Decimal("0"),
        client.monthly_fee - receivable.paid_amount,
    )
    receivable.status = "open" if receivable.paid_amount <= 0 else "partial"
    receivable.notes = marker


def sync_current_month_receivables(db: Session) -> None:
    clients = db.scalars(
        select(Client).where(
            Client.active.is_(True),
            Client.contract_type == "mensal",
            Client.monthly_fee > 0,
            Client.monthly_due_day.is_not(None),
        )
    ).all()
    for client in clients:
        sync_current_month_receivable(db, client)


def _monthly_due_date(year: int, month: int, due_day: int) -> datetime:
    last_day = calendar.monthrange(year, month)[1]
    return datetime(year, month, min(due_day, last_day))


def _monthly_period_bounds(reference: datetime) -> tuple[datetime, datetime]:
    start = datetime(reference.year, reference.month, 1)
    if reference.month == 12:
        end = datetime(reference.year + 1, 1, 1)
    else:
        end = datetime(reference.year, reference.month + 1, 1)
    return start, end

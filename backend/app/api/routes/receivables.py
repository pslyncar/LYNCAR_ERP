from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.client import Client
from app.models.fiscal import FiscalDocumentSale
from app.models.receivable import Receivable, ReceivablePayment
from app.models.sale import Sale
from app.models.service_order import ServiceOrder
from app.models.user import User
from app.schemas.receivable import (
    ReceivableAccountPaymentCreate,
    ReceivableManualCreate,
    ReceivablePaymentCreate,
    ReceivableRead,
)
from app.services.client_billing import sync_current_month_receivables

router = APIRouter()


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


def _money(value: Decimal) -> Decimal:
    return Decimal(value).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _service_order_id_from_sale(sale: Sale | None) -> int | None:
    if sale is None or sale.source != "os":
        return None
    marker = (sale.offline_client_id or "").strip()
    if not marker.startswith("os:"):
        return None
    try:
        return int(marker.split(":", 1)[1])
    except ValueError:
        return None


def _sync_service_order_after_receivable_payment(db: Session, sale: Sale | None) -> None:
    service_order_id = _service_order_id_from_sale(sale)
    if service_order_id is None:
        return
    service_order = db.get(ServiceOrder, service_order_id)
    if service_order is None or service_order.status == "cancelada":
        return
    open_receivables = list(
        db.scalars(
            select(Receivable).where(
                Receivable.sale_id == sale.id,
                Receivable.status != "paid",
                Receivable.status != "canceled",
                Receivable.balance_amount > 0,
            )
        ).all()
    )
    service_order.status = "aguardando_retirada" if open_receivables else "concluida"
    service_order.closed_at = datetime.utcnow() if not open_receivables else None


def get_receivable_or_404(db: Session, receivable_id: int) -> Receivable:
    receivable = db.scalar(
        select(Receivable)
        .options(
            selectinload(Receivable.payments),
            selectinload(Receivable.client),
            selectinload(Receivable.sale).selectinload(Sale.items),
            selectinload(Receivable.sale).selectinload(Sale.fiscal_documents),
            selectinload(Receivable.sale)
            .selectinload(Sale.fiscal_document_links)
            .selectinload(FiscalDocumentSale.document),
        )
        .where(Receivable.id == receivable_id)
    )
    if receivable is None:
        raise HTTPException(status_code=404, detail="Recebivel nao encontrado.")
    return receivable


@router.get("", response_model=list[ReceivableRead])
def list_receivables(
    status_filter: str | None = Query(default=None, alias="status"),
    client_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("finance:view", "finance:receivables:view")
    ),
) -> list[Receivable]:
    sync_current_month_receivables(db)
    db.commit()
    query = (
        select(Receivable)
        .options(
            selectinload(Receivable.payments),
            selectinload(Receivable.client),
            selectinload(Receivable.sale).selectinload(Sale.items),
            selectinload(Receivable.sale).selectinload(Sale.fiscal_documents),
            selectinload(Receivable.sale)
            .selectinload(Sale.fiscal_document_links)
            .selectinload(FiscalDocumentSale.document),
        )
        .order_by(Receivable.created_at.desc(), Receivable.id.desc())
        .limit(limit)
    )
    if status_filter:
        query = query.where(Receivable.status == status_filter)
    if client_id is not None:
        query = query.where(Receivable.client_id == client_id)
    return list(db.scalars(query).all())


@router.post("", response_model=ReceivableRead, status_code=status.HTTP_201_CREATED)
def create_manual_receivable(
    receivable_in: ReceivableManualCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:receivables:pay")),
) -> Receivable:
    client = db.get(Client, receivable_in.client_id)
    if client is None:
        raise HTTPException(status_code=404, detail="Cliente nao encontrado.")
    receivable = Receivable(
        sale_id=None,
        client_id=receivable_in.client_id,
        description=receivable_in.description.strip(),
        original_amount=receivable_in.amount,
        paid_amount=0,
        balance_amount=receivable_in.amount,
        status="open",
        due_date=receivable_in.due_date,
        notes=receivable_in.notes,
        entry_type=receivable_in.entry_type,
    )
    db.add(receivable)
    db.flush()
    receivable.number = receivable_number(receivable.id)
    note = f"Lançado manualmente por {current_user.name or 'usuario'}."
    receivable.notes = f"{receivable.notes}\n{note}" if receivable.notes else note
    db.commit()
    return get_receivable_or_404(db, receivable.id)


@router.post("/{receivable_id}/payments", response_model=ReceivableRead, status_code=status.HTTP_201_CREATED)
def pay_receivable(
    receivable_id: int,
    payment_in: ReceivablePaymentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:receivables:pay")),
) -> Receivable:
    receivable = get_receivable_or_404(db, receivable_id)
    if receivable.status == "paid" or receivable.balance_amount <= 0:
        raise HTTPException(status_code=400, detail="Recebivel ja quitado.")
    if receivable.status == "canceled":
        raise HTTPException(status_code=400, detail="Recebivel cancelado.")
    payment_amount = _money(payment_in.amount)
    balance_amount = _money(receivable.balance_amount)
    if payment_amount > balance_amount:
        raise HTTPException(
            status_code=400,
            detail="Pagamento maior que o saldo em aberto.",
        )

    receivable.payments.append(
        ReceivablePayment(
            user_id=current_user.id,
            amount=payment_amount,
            method=payment_in.method,
            notes=payment_in.notes,
        )
    )
    receivable.paid_amount = _money(receivable.paid_amount + payment_amount)
    receivable.balance_amount = _money(receivable.balance_amount - payment_amount)
    if _money(receivable.balance_amount) <= 0:
        receivable.balance_amount = 0
        receivable.status = "paid"
        receivable.settled_at = datetime.utcnow()
    else:
        receivable.status = "partial"
    _sync_service_order_after_receivable_payment(db, receivable.sale)
    db.commit()
    return get_receivable_or_404(db, receivable.id)


@router.post("/{receivable_id}/cancel", response_model=ReceivableRead)
def cancel_receivable(
    receivable_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:receivables:pay")),
) -> Receivable:
    receivable = get_receivable_or_404(db, receivable_id)
    if receivable.status == "canceled":
        return receivable
    if receivable.status == "paid" or receivable.balance_amount <= 0:
        raise HTTPException(
            status_code=400,
            detail="Recebivel quitado nao pode ser cancelado pelo financeiro.",
        )
    receivable.status = "canceled"
    receivable.balance_amount = 0
    receivable.settled_at = datetime.utcnow()
    note = f"Cancelado pelo financeiro por {current_user.name or 'usuario'}."
    receivable.notes = f"{receivable.notes}\n{note}" if receivable.notes else note
    db.commit()
    return get_receivable_or_404(db, receivable.id)


@router.post(
    "/clients/{client_id}/payments",
    response_model=list[ReceivableRead],
    status_code=status.HTTP_201_CREATED,
)
def pay_client_receivables(
    client_id: int,
    payment_in: ReceivableAccountPaymentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("finance:receivables:pay")),
) -> list[Receivable]:
    open_receivables = list(
        db.scalars(
            select(Receivable)
            .options(
                selectinload(Receivable.payments),
                selectinload(Receivable.client),
                selectinload(Receivable.sale).selectinload(Sale.items),
            )
            .where(
                Receivable.client_id == client_id,
                Receivable.balance_amount > 0,
                Receivable.status != "paid",
                Receivable.status != "canceled",
            )
            .order_by(
                Receivable.due_date.asc().nulls_last(),
                Receivable.created_at.asc(),
                Receivable.id.asc(),
            )
        ).all()
    )
    if not open_receivables:
        raise HTTPException(
            status_code=400,
            detail="Cliente nao possui contas a receber em aberto.",
        )

    total_balance = _money(sum(item.balance_amount for item in open_receivables))
    payment_amount = _money(payment_in.amount)
    if payment_amount > total_balance:
        raise HTTPException(
            status_code=400,
            detail="Recebimento maior que o saldo em aberto do cliente.",
        )

    remaining = payment_amount
    changed_ids: list[int] = []
    changed_sales: dict[int, Sale] = {}
    for receivable in open_receivables:
        if remaining <= 0:
            break
        applied = min(_money(receivable.balance_amount), remaining)
        receivable.payments.append(
            ReceivablePayment(
                user_id=current_user.id,
                amount=applied,
                method=payment_in.method,
                notes=payment_in.notes,
            )
        )
        receivable.paid_amount = _money(receivable.paid_amount + applied)
        receivable.balance_amount = _money(receivable.balance_amount - applied)
        if _money(receivable.balance_amount) <= 0:
            receivable.balance_amount = 0
            receivable.status = "paid"
            receivable.settled_at = datetime.utcnow()
        else:
            receivable.status = "partial"
        remaining -= applied
        changed_ids.append(receivable.id)
        if receivable.sale is not None:
            changed_sales[receivable.sale.id] = receivable.sale

    for sale in changed_sales.values():
        _sync_service_order_after_receivable_payment(db, sale)
    db.commit()
    return [
        get_receivable_or_404(db, receivable_id)
        for receivable_id in changed_ids
    ]

from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import bearer_scheme, require_any_permission, require_permission
from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.cash_closing import CashClosing, CashClosingMovement, CashClosingPayment
from app.models.pdv_cash_session import PdvCashSession
from app.models.sale import Sale
from app.models.user import User
from app.schemas.cash_closing import (
    CashClosingCreate,
    CashClosingRead,
    CashClosingTreasuryReview,
)
from app.services.business_day import business_date, company_cutoff_minutes, crossed_business_day

router = APIRouter()

MONEY_QUANT = Decimal("0.01")


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def closing_number(closing_id: int) -> str:
    return f"CX{closing_id}"


def get_closing_or_404(db: Session, closing_id: int) -> CashClosing:
    closing = db.scalar(
        select(CashClosing)
        .options(selectinload(CashClosing.payments), selectinload(CashClosing.movements))
        .where(CashClosing.id == closing_id)
    )
    if closing is None:
        raise HTTPException(status_code=404, detail="Fechamento de caixa não encontrado.")
    return closing


def _payment_totals_for_sales(sales: list[Sale]) -> dict[str, Decimal]:
    payment_totals: dict[str, Decimal] = {}
    for sale in sales:
        remaining_change = sale.change_amount or Decimal("0")
        for payment in sale.payments:
            amount_for_closing = payment.amount or Decimal("0")
            if payment.method == "dinheiro" and remaining_change > 0:
                change_applied = min(amount_for_closing, remaining_change)
                amount_for_closing -= change_applied
                remaining_change -= change_applied
            payment_totals[payment.method] = money(
                payment_totals.get(payment.method, Decimal("0")) + amount_for_closing
            )
    return payment_totals


def _movement_total(closing_in: CashClosingCreate, movement_type: str) -> Decimal:
    return money(
        sum(
            (
                movement.amount
                for movement in closing_in.movements
                if movement.movement_type == movement_type
            ),
            Decimal("0"),
        )
    )


def _expected_cash_after_float_return(
    cash_sales_amount: Decimal,
    total_supply_amount: Decimal,
    total_withdrawal_amount: Decimal,
) -> Decimal:
    """Cash counted after the opening float has been removed."""
    return money(
        max(
            Decimal("0"),
            cash_sales_amount + total_supply_amount - total_withdrawal_amount,
        )
    )


def _build_session_closing_totals(
    db: Session,
    cash_session: PdvCashSession,
    closing_in: CashClosingCreate,
) -> tuple[Decimal, int, Decimal, Decimal, Decimal, list[CashClosingPayment]]:
    sales = list(
        db.scalars(
            select(Sale)
            .options(selectinload(Sale.payments))
            .where(
                Sale.cash_session_id == cash_session.id,
                Sale.status == "finalizada",
            )
            .order_by(Sale.sold_at.asc(), Sale.id.asc())
        ).all()
    )
    total_sales_amount = money(
        sum((sale.total_amount or Decimal("0") for sale in sales), Decimal("0"))
    )
    payment_totals = _payment_totals_for_sales(sales)
    total_withdrawal_amount = _movement_total(closing_in, "sangria")
    total_supply_amount = _movement_total(closing_in, "suprimento")
    cash_sales_amount = payment_totals.get("dinheiro", Decimal("0"))
    expected_cash_amount = _expected_cash_after_float_return(
        cash_sales_amount,
        total_supply_amount,
        total_withdrawal_amount,
    )
    closing_payments = [
        CashClosingPayment(method=method, amount=amount)
        for method, amount in sorted(payment_totals.items())
        if amount > 0
    ]
    return (
        total_sales_amount,
        len(sales),
        expected_cash_amount,
        total_withdrawal_amount,
        total_supply_amount,
        closing_payments,
    )


@router.post("/closings", response_model=CashClosingRead, status_code=status.HTTP_201_CREATED)
def create_cash_closing(
    closing_in: CashClosingCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> CashClosing:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token ausente.")
    token_payload = decode_access_token(credentials.credentials)
    company_code = token_payload.get("company_code")
    if not isinstance(company_code, str) or not company_code:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Empresa invalida.")
    cutoff_minutes = company_cutoff_minutes(company_code)
    closed_at = datetime.now(timezone.utc)
    cash_session: PdvCashSession | None = None
    cash_session_id = closing_in.cash_session_id

    def find_open_session_for_terminal() -> PdvCashSession | None:
        if not closing_in.cash_register_number:
            return None
        open_session_query = select(PdvCashSession).where(
            PdvCashSession.status == "open",
            PdvCashSession.cash_register_number == closing_in.cash_register_number,
        )
        if closing_in.terminal_key:
            open_session_query = open_session_query.where(
                PdvCashSession.terminal_key == closing_in.terminal_key
            )
        return db.scalar(
            open_session_query.order_by(
                PdvCashSession.opened_at.desc(), PdvCashSession.id.desc()
            )
        )

    if closing_in.cash_session_id is not None:
        cash_session = db.get(PdvCashSession, closing_in.cash_session_id)
        if cash_session is None:
            cash_session = find_open_session_for_terminal()
            cash_session_id = cash_session.id if cash_session is not None else None
        if cash_session is not None and cash_session.status == "closed":
            if cash_session.closing_id is not None:
                return get_closing_or_404(db, cash_session.closing_id)
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Sessão de caixa já encerrada.",
            )
    elif closing_in.cash_register_number:
        cash_session = find_open_session_for_terminal()
        cash_session_id = cash_session.id if cash_session is not None else None

    if cash_session is None and closing_in.cash_register_number and closing_in.terminal_key:
        cash_session = PdvCashSession(
            cash_register_number=closing_in.cash_register_number,
            terminal_key=closing_in.terminal_key,
            operator_name=closing_in.operator_name,
            status="open",
            opened_at=closing_in.opened_at or datetime.utcnow(),
            opening_amount=closing_in.opening_amount,
            last_heartbeat_at=datetime.utcnow(),
            created_by_user_id=current_user.id,
        )
        db.add(cash_session)
        db.flush()
        cash_session_id = cash_session.id
    total_sales_amount = closing_in.total_sales_amount
    total_sales_count = closing_in.total_sales_count
    expected_cash_amount = closing_in.expected_cash_amount
    total_withdrawal_amount = closing_in.total_withdrawal_amount
    total_supply_amount = closing_in.total_supply_amount
    closing_payments = [
        CashClosingPayment(**payment.model_dump()) for payment in closing_in.payments
    ]
    if cash_session is not None:
        (
            total_sales_amount,
            total_sales_count,
            expected_cash_amount,
            total_withdrawal_amount,
            total_supply_amount,
            closing_payments,
        ) = _build_session_closing_totals(db, cash_session, closing_in)
    difference = money(closing_in.counted_cash_amount - expected_cash_amount)
    opened_at = cash_session.opened_at if cash_session is not None else closing_in.opened_at
    closing = CashClosing(
        cash_session_id=cash_session_id,
        cash_register_number=(
            cash_session.cash_register_number
            if cash_session is not None
            else closing_in.cash_register_number
        ),
        operator_name=(
            cash_session.operator_name
            if cash_session is not None
            else closing_in.operator_name
        ),
        opened_at=opened_at,
        closed_at=closed_at,
        business_date=(business_date(opened_at, cutoff_minutes) if opened_at else None),
        crossed_business_day=crossed_business_day(opened_at, closed_at, cutoff_minutes),
        business_day_cutoff_minutes=cutoff_minutes,
        opened_by_user_id=current_user.id,
        closed_by_user_id=current_user.id,
        opening_amount=(
            cash_session.opening_amount if cash_session is not None else closing_in.opening_amount
        ),
        expected_cash_amount=expected_cash_amount,
        counted_cash_amount=closing_in.counted_cash_amount,
        cash_difference_amount=difference,
        total_sales_amount=total_sales_amount,
        total_sales_count=total_sales_count,
        total_withdrawal_amount=total_withdrawal_amount,
        total_supply_amount=total_supply_amount,
        authorized_by_operator_id=closing_in.authorized_by_operator_id,
        authorized_by_operator_name=closing_in.authorized_by_operator_name,
        status="pending_treasury",
        notes=closing_in.notes,
    )
    for payment in closing_payments:
        closing.payments.append(payment)
    for movement in closing_in.movements:
        closing.movements.append(
            CashClosingMovement(
                movement_type=movement.movement_type,
                amount=movement.amount,
                reason=movement.reason,
                created_at=movement.created_at,
                authorized_by_operator_id=movement.authorized_by_operator_id,
                authorized_by_operator_name=movement.authorized_by_operator_name,
            )
        )
    db.add(closing)
    db.flush()
    closing.number = closing_number(closing.id)
    if cash_session is not None and cash_session.status != "closed":
        cash_session.status = "closed"
        cash_session.closed_at = closed_at
        cash_session.closed_by_user_id = current_user.id
        cash_session.closing_id = closing.id
        cash_session.last_heartbeat_at = closed_at
    db.commit()
    return get_closing_or_404(db, closing.id)


@router.get("/closings", response_model=list[CashClosingRead])
def list_cash_closings(
    status_filter: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:view", "pdv_operators:manage")),
) -> list[CashClosing]:
    query = (
        select(CashClosing)
        .options(selectinload(CashClosing.payments), selectinload(CashClosing.movements))
        .order_by(CashClosing.closed_at.desc(), CashClosing.id.desc())
        .limit(limit)
    )
    if status_filter:
        query = query.where(CashClosing.status == status_filter)
    return list(db.scalars(query).all())


@router.put("/closings/{closing_id}/treasury-review", response_model=CashClosingRead)
def treasury_review_cash_closing(
    closing_id: int,
    review: CashClosingTreasuryReview,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("cash_closings:manage", "pdv_operators:manage")
    ),
) -> CashClosing:
    closing = get_closing_or_404(db, closing_id)
    if review.counted_cash_amount is not None:
        closing.counted_cash_amount = review.counted_cash_amount
        closing.cash_difference_amount = money(
            closing.counted_cash_amount - closing.expected_cash_amount
        )
    if review.status == "approved" and closing.cash_difference_amount != 0:
        closing.status = "divergent"
    else:
        closing.status = review.status
    closing.treasury_notes = review.notes
    closing.treasury_checked_by_user_id = current_user.id
    closing.treasury_checked_at = datetime.utcnow()
    db.commit()
    return get_closing_or_404(db, closing.id)

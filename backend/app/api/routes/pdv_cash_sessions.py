from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import get_db, require_permission
from app.models.pdv_cash_session import PdvCashSession
from app.models.user import User
from app.schemas.pdv_cash_session import (
    PdvCashSessionClose,
    PdvCashSessionHeartbeat,
    PdvCashSessionOpen,
    PdvCashSessionRead,
)

router = APIRouter()


def _open_session_query(cash_register_number: str, terminal_key: str | None = None):
    query = select(PdvCashSession).where(
        PdvCashSession.status == "open",
        PdvCashSession.cash_register_number == cash_register_number,
    )
    if terminal_key:
        query = query.where(PdvCashSession.terminal_key == terminal_key)
    return query.order_by(PdvCashSession.opened_at.desc(), PdvCashSession.id.desc())


@router.get("/cash-sessions/open", response_model=PdvCashSessionRead | None)
def get_open_cash_session(
    cash_register_number: str,
    terminal_key: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> PdvCashSession | None:
    return db.scalar(_open_session_query(cash_register_number, terminal_key))


@router.post(
    "/cash-sessions/open",
    response_model=PdvCashSessionRead,
    status_code=status.HTTP_201_CREATED,
)
def open_cash_session(
    session_in: PdvCashSessionOpen,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> PdvCashSession:
    existing = db.scalar(
        _open_session_query(session_in.cash_register_number, session_in.terminal_key)
    )
    if existing is not None:
        existing.status = "recovered"
        db.flush()
        existing.status = "open"
        existing.last_heartbeat_at = datetime.utcnow()
        return existing

    cash_session = PdvCashSession(
        cash_register_number=session_in.cash_register_number,
        terminal_key=session_in.terminal_key,
        operator_id=session_in.operator_id,
        operator_name=session_in.operator_name,
        opening_amount=session_in.opening_amount,
        status="open",
        last_heartbeat_at=datetime.utcnow(),
        created_by_user_id=current_user.id,
    )
    db.add(cash_session)
    db.flush()
    return cash_session


@router.post("/cash-sessions/{session_id}/heartbeat", response_model=PdvCashSessionRead)
def heartbeat_cash_session(
    session_id: int,
    payload: PdvCashSessionHeartbeat,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> PdvCashSession:
    cash_session = db.get(PdvCashSession, session_id)
    if cash_session is None:
        raise HTTPException(status_code=404, detail="Sessão de caixa não encontrada.")
    if cash_session.status != "open":
        raise HTTPException(status_code=409, detail="Sessão de caixa já encerrada.")
    cash_session.last_heartbeat_at = datetime.utcnow()
    if payload.last_error:
        cash_session.last_error = payload.last_error[:4000]
    return cash_session


@router.post("/cash-sessions/{session_id}/close", response_model=PdvCashSessionRead)
def close_cash_session(
    session_id: int,
    payload: PdvCashSessionClose,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> PdvCashSession:
    cash_session = db.get(PdvCashSession, session_id)
    if cash_session is None:
        raise HTTPException(status_code=404, detail="Sessão de caixa não encontrada.")
    if cash_session.status == "closed":
        return cash_session
    cash_session.status = "closed"
    cash_session.closed_at = datetime.utcnow()
    cash_session.closed_by_user_id = current_user.id
    cash_session.closing_id = payload.closing_id
    cash_session.last_heartbeat_at = datetime.utcnow()
    return cash_session

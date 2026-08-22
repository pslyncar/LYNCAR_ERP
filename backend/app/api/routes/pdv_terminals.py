from datetime import datetime, time, timedelta, timezone
import json
import secrets
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, require_any_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token, hash_password
from app.models.company import Company
from app.models.pdv_terminal import PdvTerminal
from app.models.pdv_terminal_command import PdvTerminalCommand
from app.models.sale import Sale
from app.models.user import User
from app.schemas.pdv_terminal import (
    PdvTerminalCommandAck,
    PdvTerminalCommandCreate,
    PdvTerminalCommandRead,
    PdvTerminalActivationCodeRead,
    PdvTerminalActivationCreate,
    PdvTerminalHeartbeat,
    PdvTerminalNumberUpdate,
    PdvTerminalRead,
    PdvTerminalRegister,
    PdvBusinessDaySettings,
)
from app.services.business_day import company_cutoff_minutes, crossed_business_day
from app.services.plan_limits import enforce_pdv_terminal_limit, lock_pdv_terminal_quota

router = APIRouter()
LOCAL_TIMEZONE = ZoneInfo("America/Sao_Paulo")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _local_day_bounds() -> tuple[datetime, datetime]:
    today = datetime.now(LOCAL_TIMEZONE).date()
    start = datetime.combine(today, time.min, tzinfo=LOCAL_TIMEZONE)
    return start, start + timedelta(days=1)


def _terminal_read(
    db: Session, terminal: PdvTerminal, cutoff_minutes: int = 180
) -> PdvTerminalRead:
    start, end = _local_day_bounds()
    count, amount = db.execute(
        select(func.count(Sale.id), func.coalesce(func.sum(Sale.total_amount), 0))
        .where(Sale.cash_register_number == terminal.cash_register_number)
        .where(Sale.status != "cancelada")
        .where(Sale.sold_at >= start)
        .where(Sale.sold_at < end)
    ).one()
    return PdvTerminalRead.model_validate(
        {
            "id": terminal.id,
            "cash_register_number": terminal.cash_register_number,
            "terminal_key": terminal.terminal_key,
            "app_version": terminal.app_version,
            "device_label": terminal.device_label,
            "activation_status": terminal.activation_status,
            "activation_code_expires_at": terminal.activation_code_expires_at,
            "activated_at": terminal.activated_at,
            "machine_name": terminal.machine_name,
            "windows_user": terminal.windows_user,
            "windows_version": terminal.windows_version,
            "device_fingerprint": terminal.device_fingerprint,
            "active": terminal.active,
            "current_status": terminal.current_status,
            "current_operator_name": terminal.current_operator_name,
            "cash_opened_at": terminal.cash_opened_at,
            "current_session_total_amount": terminal.current_session_total_amount,
            "today_sales_count": int(count or 0),
            "today_sales_amount": amount or 0,
            "created_at": terminal.created_at,
            "updated_at": terminal.updated_at,
            "last_seen_at": terminal.last_seen_at,
            "crossed_business_day": crossed_business_day(
                terminal.cash_opened_at, _utc_now(), cutoff_minutes
            ),
        }
    )


def _tenant_company_code(
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token ausente.")
    payload = decode_access_token(credentials.credentials)
    company_code = payload.get("company_code")
    if not isinstance(company_code, str) or not company_code:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Empresa invalida.")
    return company_code


def _new_activation_code() -> str:
    value = secrets.randbelow(900000) + 100000
    return f"LYN-{value // 1000:03d}-{value % 1000:03d}"


def _ensure_command_table(db: Session) -> None:
    PdvTerminalCommand.__table__.create(bind=db.get_bind(), checkfirst=True)


def _command_read(command: PdvTerminalCommand) -> PdvTerminalCommandRead:
    payload = None
    if command.payload_json:
        try:
            decoded = json.loads(command.payload_json)
            if isinstance(decoded, dict):
                payload = decoded
        except json.JSONDecodeError:
            payload = None
    return PdvTerminalCommandRead(
        id=command.id,
        terminal_id=command.terminal_id,
        action=command.action,
        status=command.status,
        message=command.message,
        payload=payload,
        result_message=command.result_message,
        created_at=command.created_at,
        delivered_at=command.delivered_at,
        completed_at=command.completed_at,
    )


@router.post("/terminals/activation-code", response_model=PdvTerminalActivationCodeRead)
def create_pdv_terminal_activation_code(
    payload: PdvTerminalActivationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> PdvTerminalActivationCodeRead:
    company_code = _tenant_company_code(credentials)
    lock_pdv_terminal_quota(db, company_code)
    terminal = db.scalar(
        select(PdvTerminal).where(
            PdvTerminal.cash_register_number == payload.cash_register_number
        )
    )
    now = _utc_now()
    if terminal is None:
        enforce_pdv_terminal_limit(
            db,
            company_code,
            adding_new_terminal=True,
        )
        terminal = db.scalar(
            select(PdvTerminal).where(
                PdvTerminal.cash_register_number == payload.cash_register_number
            )
        )
        if terminal is None:
            terminal = PdvTerminal(
                cash_register_number=payload.cash_register_number,
                terminal_key=f"pending:{secrets.token_urlsafe(24)}",
                active=False,
                current_status="pending",
                created_at=now,
            )
            db.add(terminal)
    code = _new_activation_code()
    expires_at = now + timedelta(hours=payload.expires_hours)
    terminal.activation_code_hash = hash_password(code)
    terminal.activation_code_expires_at = expires_at
    terminal.activation_status = "pending"
    terminal.device_label = payload.device_label or terminal.device_label
    terminal.updated_at = now
    db.commit()
    db.refresh(terminal)
    return PdvTerminalActivationCodeRead(
        terminal=_terminal_read(db, terminal),
        activation_code=code,
        expires_at=expires_at,
    )


@router.post("/terminals/register", response_model=PdvTerminalRead)
def register_pdv_terminal(
    payload: PdvTerminalRegister,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:create", "pdv_operators:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> PdvTerminal:
    now = _utc_now()
    company_code = _tenant_company_code(credentials)
    lock_pdv_terminal_quota(db, company_code)
    terminal = db.scalar(
        select(PdvTerminal).where(PdvTerminal.terminal_key == payload.terminal_key)
    )
    number_owner = db.scalar(
        select(PdvTerminal).where(
            PdvTerminal.cash_register_number == payload.cash_register_number
        )
    )
    if number_owner is not None and (
        terminal is None or number_owner.id != terminal.id
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Caixa {payload.cash_register_number} ja esta cadastrado "
                "em outro PDV desta empresa."
            ),
        )
    if terminal is None:
        enforce_pdv_terminal_limit(
            db,
            company_code,
            adding_new_terminal=True,
        )
        number_owner = db.scalar(
            select(PdvTerminal).where(
                PdvTerminal.cash_register_number == payload.cash_register_number
            )
        )
        if number_owner is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Caixa {payload.cash_register_number} ja esta cadastrado "
                    "em outro PDV desta empresa."
                ),
            )
        terminal = PdvTerminal(
            cash_register_number=payload.cash_register_number,
            terminal_key=payload.terminal_key,
            created_at=now,
        )
        db.add(terminal)

    # O numero do caixa identifica fisicamente o terminal. Depois que um
    # computador vira Caixa 01, ele continua sendo Caixa 01; nao trocamos esse
    # numero por reenvio local, reinstalacao parcial ou preferencia corrompida.
    # Para mudar de proposito, deve haver uma rotina administrativa separada.
    terminal.terminal_key = payload.terminal_key
    terminal.app_version = payload.app_version
    terminal.device_label = payload.device_label
    if terminal.activation_status != "blocked":
        terminal.active = True
    terminal.updated_at = now
    terminal.last_seen_at = now
    db.commit()
    db.refresh(terminal)
    return terminal


@router.post("/terminals/heartbeat", response_model=PdvTerminalRead)
def heartbeat_pdv_terminal(
    payload: PdvTerminalHeartbeat,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:create", "pdv_operators:manage")),
) -> PdvTerminalRead:
    terminal = db.scalar(
        select(PdvTerminal).where(PdvTerminal.terminal_key == payload.terminal_key)
    )
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao cadastrado.",
        )
    now = _utc_now()
    terminal.app_version = payload.app_version or terminal.app_version
    terminal.device_label = payload.device_label or terminal.device_label
    if terminal.activation_status == "blocked":
        terminal.current_status = "blocked"
        terminal.active = False
    else:
        terminal.current_status = payload.current_status
        terminal.active = True
    terminal.current_operator_name = payload.current_operator_name
    terminal.cash_opened_at = payload.cash_opened_at
    terminal.current_session_total_amount = payload.current_session_total_amount
    terminal.updated_at = now
    terminal.last_seen_at = now
    db.commit()
    db.refresh(terminal)
    return _terminal_read(db, terminal)


@router.get("/terminals/commands", response_model=list[PdvTerminalCommandRead])
def list_pdv_terminal_commands(
    terminal_key: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:create", "pdv_operators:manage")),
) -> list[PdvTerminalCommandRead]:
    _ensure_command_table(db)
    cleaned_key = str(terminal_key or "").strip()
    terminal = db.scalar(
        select(PdvTerminal).where(PdvTerminal.terminal_key == cleaned_key)
    )
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao encontrado.",
        )
    commands = list(
        db.scalars(
            select(PdvTerminalCommand)
            .where(PdvTerminalCommand.terminal_id == terminal.id)
            .where(PdvTerminalCommand.status == "pending")
            .order_by(PdvTerminalCommand.id.asc())
            .limit(20)
        ).all()
    )
    now = _utc_now()
    changed = False
    for command in commands:
        if command.delivered_at is None:
            command.delivered_at = now
            changed = True
    if changed:
        db.commit()
        for command in commands:
            db.refresh(command)
    return [_command_read(command) for command in commands]


@router.post(
    "/terminals/{terminal_id}/commands",
    response_model=PdvTerminalCommandRead,
)
def create_pdv_terminal_command(
    terminal_id: int,
    payload: PdvTerminalCommandCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
) -> PdvTerminalCommandRead:
    del current_user
    _ensure_command_table(db)
    terminal = db.get(PdvTerminal, terminal_id)
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao encontrado.",
        )
    command = PdvTerminalCommand(
        terminal_id=terminal.id,
        action=payload.action,
        status="pending",
        message=payload.message,
        payload_json=json.dumps(payload.payload) if payload.payload else None,
    )
    db.add(command)
    db.commit()
    db.refresh(command)
    return _command_read(command)


@router.post("/terminals/commands/{command_id}/ack", response_model=PdvTerminalCommandRead)
def acknowledge_pdv_terminal_command(
    command_id: int,
    payload: PdvTerminalCommandAck,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:create", "pdv_operators:manage")),
) -> PdvTerminalCommandRead:
    _ensure_command_table(db)
    terminal = db.scalar(
        select(PdvTerminal).where(PdvTerminal.terminal_key == payload.terminal_key)
    )
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao encontrado.",
        )
    command = db.get(PdvTerminalCommand, command_id)
    if command is None or command.terminal_id != terminal.id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Comando do terminal nao encontrado.",
        )
    now = _utc_now()
    command.status = payload.status
    command.result_message = payload.result_message
    command.delivered_at = command.delivered_at or now
    command.completed_at = now
    if payload.status == "done":
        if command.action == "block_terminal":
            terminal.activation_status = "blocked"
            terminal.active = False
            terminal.current_status = "blocked"
        elif command.action == "unblock_terminal":
            terminal.activation_status = "active"
            terminal.active = True
            terminal.current_status = "closed"
        elif command.action == "reset_terminal_link":
            terminal.activation_status = "pending"
            terminal.active = False
            terminal.current_status = "pending"
            terminal.terminal_key = f"pending:{secrets.token_urlsafe(24)}"
            terminal.activation_code_hash = None
            terminal.activation_code_expires_at = None
            terminal.activated_at = None
        terminal.updated_at = now
    db.commit()
    db.refresh(command)
    return _command_read(command)


@router.get("/terminals", response_model=list[PdvTerminalRead])
def list_pdv_terminals(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:view", "pdv_operators:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> list[PdvTerminalRead]:
    cutoff_minutes = company_cutoff_minutes(_tenant_company_code(credentials))
    terminals = list(
        db.scalars(
            select(PdvTerminal).order_by(
                PdvTerminal.active.desc(),
                PdvTerminal.cash_register_number.asc(),
                PdvTerminal.id.asc(),
            )
        ).all()
    )
    return [_terminal_read(db, terminal, cutoff_minutes) for terminal in terminals]


@router.get("/business-day-settings", response_model=PdvBusinessDaySettings)
def get_pdv_business_day_settings(
    current_user: User = Depends(require_any_permission("sales:view", "pdv_operators:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> PdvBusinessDaySettings:
    company_code = _tenant_company_code(credentials)
    return PdvBusinessDaySettings(cutoff_minutes=company_cutoff_minutes(company_code))


@router.put("/business-day-settings", response_model=PdvBusinessDaySettings)
def update_pdv_business_day_settings(
    payload: PdvBusinessDaySettings,
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> PdvBusinessDaySettings:
    company_code = _tenant_company_code(credentials)
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa nao encontrada.")
        company.business_day_cutoff_minutes = payload.cutoff_minutes
        master_db.commit()
    return payload


@router.put("/terminals/{terminal_id}/number", response_model=PdvTerminalRead)
def update_pdv_terminal_number(
    terminal_id: int,
    payload: PdvTerminalNumberUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
) -> PdvTerminalRead:
    terminal = db.get(PdvTerminal, terminal_id)
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao encontrado.",
        )
    number_owner = db.scalar(
        select(PdvTerminal).where(
            PdvTerminal.cash_register_number == payload.cash_register_number
        )
    )
    if number_owner is not None and number_owner.id != terminal.id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Caixa {payload.cash_register_number} ja esta cadastrado "
                "em outro PDV desta empresa."
            ),
        )
    terminal.cash_register_number = payload.cash_register_number
    terminal.updated_at = _utc_now()
    db.commit()
    db.refresh(terminal)
    return _terminal_read(db, terminal)


@router.delete("/terminals/{terminal_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_pdv_terminal(
    terminal_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
) -> None:
    terminal = db.get(PdvTerminal, terminal_id)
    if terminal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Terminal PDV nao encontrado.",
        )
    db.delete(terminal)
    db.commit()

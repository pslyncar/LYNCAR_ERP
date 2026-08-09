from datetime import datetime, timedelta, timezone
import json
import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.core.security import hash_password
from app.models.company import Company
from app.models.pdv_terminal import PdvTerminal
from app.models.pdv_terminal_command import PdvTerminalCommand
from app.schemas.pdv_terminal import (
    MasterPdvTerminalActivationCreate,
    PdvTerminalActivationCodeRead,
    PdvTerminalCommandCreate,
    PdvTerminalCommandRead,
    PdvTerminalNumberUpdate,
    PdvTerminalRead,
    PdvBusinessDaySettings,
)
from app.services.business_day import company_cutoff_minutes, crossed_business_day
from app.services.tenancy import normalize_company_code, session_for_company

router = APIRouter()


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _new_activation_code() -> str:
    value = secrets.randbelow(900000) + 100000
    return f"LYN-{value // 1000:03d}-{value % 1000:03d}"


def _ensure_command_table(db) -> None:
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


def _terminal_read(
    db, terminal: PdvTerminal, cutoff_minutes: int = 180
) -> PdvTerminalRead:
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
            "current_session_total_amount": None,
            "today_sales_count": 0,
            "today_sales_amount": 0,
            "created_at": terminal.created_at,
            "updated_at": terminal.updated_at,
            "last_seen_at": terminal.last_seen_at,
            "crossed_business_day": crossed_business_day(
                terminal.cash_opened_at, _utc_now(), cutoff_minutes
            ),
        }
    )


def _require_company_code(company_code: str) -> str:
    normalized = normalize_company_code(company_code)
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == normalized))
        if company is None or not company.active or company.status != "active":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Empresa cliente nao encontrada ou inativa.",
            )
    return normalized


def _require_company_with_pdv_windows(company_code: str) -> str:
    normalized = normalize_company_code(company_code)
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == normalized))
        if company is None or not company.active or company.status != "active":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Empresa cliente nao encontrada ou inativa.",
            )
        if "pdv_windows" not in (company.enabled_modules or []):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "Cliente nao possui PDV Windows liberado no plano/cadastro. "
                    "Libere o modulo PDV Windows no plano ou como excecao no cadastro da empresa."
                ),
            )
    return normalized


@router.get("/pdv/terminals", response_model=list[PdvTerminalRead])
def list_master_pdv_terminals(
    company_code: str,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> list[PdvTerminalRead]:
    normalized = _require_company_code(company_code)
    cutoff_minutes = company_cutoff_minutes(normalized)
    with session_for_company(normalized) as db:
        terminals = list(
            db.scalars(
                select(PdvTerminal)
                .where(PdvTerminal.activation_status != "pending")
                .order_by(
                    PdvTerminal.active.desc(),
                    PdvTerminal.cash_register_number.asc(),
                    PdvTerminal.id.asc(),
                )
            ).all()
        )
        return [_terminal_read(db, terminal, cutoff_minutes) for terminal in terminals]


@router.get("/pdv/business-day-settings", response_model=PdvBusinessDaySettings)
def get_master_pdv_business_day_settings(
    company_code: str,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvBusinessDaySettings:
    normalized = _require_company_code(company_code)
    return PdvBusinessDaySettings(cutoff_minutes=company_cutoff_minutes(normalized))


@router.put("/pdv/business-day-settings", response_model=PdvBusinessDaySettings)
def update_master_pdv_business_day_settings(
    company_code: str,
    payload: PdvBusinessDaySettings,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvBusinessDaySettings:
    normalized = _require_company_code(company_code)
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == normalized))
        if company is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa nao encontrada.")
        company.business_day_cutoff_minutes = payload.cutoff_minutes
        master_db.commit()
    return payload


@router.post("/pdv/terminals/activation-code", response_model=PdvTerminalActivationCodeRead)
def create_master_pdv_terminal_activation_code(
    payload: MasterPdvTerminalActivationCreate,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvTerminalActivationCodeRead:
    company_code = _require_company_with_pdv_windows(payload.company_code)

    now = _utc_now()
    with session_for_company(company_code) as db:
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


@router.get(
    "/pdv/terminals/{terminal_id}/commands",
    response_model=list[PdvTerminalCommandRead],
)
def list_master_pdv_terminal_commands(
    terminal_id: int,
    company_code: str,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> list[PdvTerminalCommandRead]:
    normalized = _require_company_code(company_code)
    with session_for_company(normalized) as db:
        _ensure_command_table(db)
        terminal = db.get(PdvTerminal, terminal_id)
        if terminal is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Terminal PDV nao encontrado.",
            )
        commands = list(
            db.scalars(
                select(PdvTerminalCommand)
                .where(PdvTerminalCommand.terminal_id == terminal.id)
                .order_by(PdvTerminalCommand.id.desc())
                .limit(30)
            ).all()
        )
        return [_command_read(command) for command in commands]


@router.post(
    "/pdv/terminals/{terminal_id}/commands",
    response_model=PdvTerminalCommandRead,
)
def create_master_pdv_terminal_command(
    terminal_id: int,
    company_code: str,
    payload: PdvTerminalCommandCreate,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvTerminalCommandRead:
    normalized = _require_company_code(company_code)
    with session_for_company(normalized) as db:
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


@router.put("/pdv/terminals/{terminal_id}/number", response_model=PdvTerminalRead)
def update_master_pdv_terminal_number(
    terminal_id: int,
    payload: PdvTerminalNumberUpdate,
    company_code: str,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvTerminalRead:
    normalized = _require_company_code(company_code)
    with session_for_company(normalized) as db:
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


@router.delete("/pdv/terminals/{terminal_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_master_pdv_terminal(
    terminal_id: int,
    company_code: str,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> None:
    normalized = _require_company_code(company_code)
    with session_for_company(normalized) as db:
        terminal = db.get(PdvTerminal, terminal_id)
        if terminal is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Terminal PDV nao encontrado.",
            )
        db.delete(terminal)
        db.commit()

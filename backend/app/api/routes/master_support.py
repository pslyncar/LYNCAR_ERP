import asyncio
import json
from datetime import UTC, datetime

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.dependencies import bearer_scheme, require_master_permission
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.company import Company
from app.models.master_support import MasterSupportMessage, MasterSupportTicket
from app.models.master_user import MasterUser
from app.models.user import User
from app.schemas.master_support import (
    MasterSupportReplyCreate,
    MasterSupportTicketCreate,
    MasterSupportTicketRead,
    MasterSupportTicketUpdate,
)
from app.services.tenancy import normalize_company_code, session_for_company
from app.services.master_permissions import master_user_has_permission
from app.services.uploads import save_public_file

router = APIRouter()

VALID_STATUSES = {"aberto", "em_analise", "aguardando_cliente", "resolvido", "fechado"}
VALID_PRIORITIES = {"baixa", "normal", "alta", "urgente"}
VALID_MODULES = {
    "pdv",
    "fiscal",
    "produtos",
    "financeiro",
    "relatorios",
    "login",
    "impressora",
    "terminal",
    "outro",
}


class SupportConnectionManager:
    def __init__(self) -> None:
        self._master: set[WebSocket] = set()
        self._companies: dict[str, set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect_master(self, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._master.add(websocket)

    async def connect_company(self, company_code: str, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._companies.setdefault(company_code, set()).add(websocket)

    async def disconnect(self, websocket: WebSocket) -> None:
        async with self._lock:
            self._master.discard(websocket)
            for sockets in self._companies.values():
                sockets.discard(websocket)

    async def broadcast_ticket(self, event_type: str, ticket: MasterSupportTicket) -> None:
        payload = {
            "type": event_type,
            "ticket_id": ticket.id,
            "company_code": ticket.company_code,
            "payload": MasterSupportTicketRead.model_validate(ticket).model_dump(mode="json"),
        }
        await self._broadcast(ticket.company_code, payload)

    async def _broadcast(self, company_code: str, payload: dict) -> None:
        message = json.dumps(payload, ensure_ascii=False)
        async with self._lock:
            sockets = list(self._master) + list(self._companies.get(company_code, set()))
        stale: list[WebSocket] = []
        for websocket in sockets:
            try:
                await websocket.send_text(message)
            except Exception:
                stale.append(websocket)
        for websocket in stale:
            await self.disconnect(websocket)


support_ws = SupportConnectionManager()


def _ticket_query():
    return select(MasterSupportTicket).options(
        selectinload(MasterSupportTicket.messages),
        selectinload(MasterSupportTicket.assigned_master_user),
    )


def _apply_status_dates(ticket: MasterSupportTicket, next_status: str | None) -> None:
    now = datetime.now(UTC)
    if next_status == "resolvido" and ticket.resolved_at is None:
        ticket.resolved_at = now
    if next_status == "fechado" and ticket.closed_at is None:
        ticket.closed_at = now
    if next_status in {"aberto", "em_analise", "aguardando_cliente"}:
        ticket.closed_at = None
        if next_status != "resolvido":
            ticket.resolved_at = None


def _validate_choice(value: str, allowed: set[str], field: str) -> str:
    normalized = value.strip().lower()
    if normalized not in allowed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field} invalido.",
        )
    return normalized


def _tenant_actor(credentials: HTTPAuthorizationCredentials | None) -> tuple[dict, User]:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Token de acesso ausente.")
    try:
        payload = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado.") from exc
    if payload.get("scope") == "master":
        raise HTTPException(status_code=403, detail="Use o painel master para suporte master.")
    company_code = normalize_company_code(str(payload.get("company_code") or ""))
    try:
        user_id = int(str(payload.get("sub") or ""))
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Usuario invalido.") from exc
    with session_for_company(company_code) as db:
        user = db.get(User, user_id)
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="Usuario inativo ou nao encontrado.")
        db.expunge(user)
    return payload, user


def _master_actor(payload: dict) -> MasterUser:
    subject = str(payload.get("sub") or "")
    try:
        user_id = int(subject.split(":", 1)[1])
    except (IndexError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Token master invalido.") from exc
    with MasterSessionLocal() as db:
        user = db.get(MasterUser, user_id)
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="Usuario master invalido.")
        db.expunge(user)
        return user


def _decode_ws_token(token: str) -> dict:
    try:
        return decode_access_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado.") from exc


def _master_actor_with_permission(token: str) -> dict:
    payload = _decode_ws_token(token)
    subject = str(payload.get("sub") or "")
    if payload.get("scope") != "master" or not subject.startswith("master:"):
        raise HTTPException(status_code=403, detail="Acesso permitido apenas para usuarios master.")
    try:
        master_id = int(subject.split(":", 1)[1])
    except (IndexError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Token master invalido.") from exc
    with MasterSessionLocal() as db:
        user = db.get(MasterUser, master_id)
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="Usuario master invalido.")
        if not master_user_has_permission(db, user, "master:support"):
            raise HTTPException(status_code=403, detail="Usuario master sem permissao para suporte.")
    return payload


def _company_code_from_ws_token(token: str) -> str:
    payload = _decode_ws_token(token)
    if payload.get("scope") == "master":
        raise HTTPException(status_code=403, detail="Use o canal master.")
    return normalize_company_code(str(payload.get("company_code") or ""))


async def _ws_loop(websocket: WebSocket, *, company_code: str | None, is_master: bool) -> None:
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                continue
            event_type = str(event.get("type") or "")
            if event_type != "typing":
                continue
            ticket_id = event.get("ticket_id")
            if not isinstance(ticket_id, int):
                continue
            payload = {
                "type": "typing",
                "ticket_id": ticket_id,
                "company_code": company_code or str(event.get("company_code") or ""),
                "payload": {
                    "is_master": is_master,
                    "author_name": str(event.get("author_name") or ("Lyncar" if is_master else "Cliente")),
                    "typing": bool(event.get("typing", True)),
                },
            }
            if is_master:
                target_company = str(event.get("company_code") or "")
            else:
                target_company = company_code or ""
            if target_company:
                await support_ws._broadcast(target_company, payload)
    except WebSocketDisconnect:
        await support_ws.disconnect(websocket)


@router.post("/support/tickets", response_model=MasterSupportTicketRead, status_code=201)
def create_support_ticket(
    payload: MasterSupportTicketCreate,
    background_tasks: BackgroundTasks,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> MasterSupportTicket:
    token_data, user = _tenant_actor(credentials)
    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == company_code))
        if company is None or not company.active:
            raise HTTPException(status_code=404, detail="Empresa nao encontrada no master.")
        ticket = MasterSupportTicket(
            company_id=company.id,
            company_code=company.code,
            company_name=company.name,
            module=_validate_choice(payload.module, VALID_MODULES, "Modulo"),
            priority=_validate_choice(payload.priority, VALID_PRIORITIES, "Prioridade"),
            status="aberto",
            subject=payload.subject.strip(),
            description=payload.description.strip(),
            requester_user_id=user.id,
            requester_name=user.name,
            requester_email=user.email,
        )
        message = MasterSupportMessage(
            ticket=ticket,
            author_type="cliente",
            author_user_id=user.id,
            author_name=user.name,
            author_email=user.email,
            body=payload.description.strip(),
            attachment_url=payload.attachment_url,
            attachment_name=payload.attachment_name,
        )
        db.add(ticket)
        db.add(message)
        db.commit()
        created = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "ticket.created", created)
    return created


@router.get("/support/tickets", response_model=list[MasterSupportTicketRead])
def list_my_support_tickets(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> list[MasterSupportTicket]:
    token_data, _ = _tenant_actor(credentials)
    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    with MasterSessionLocal() as db:
        return list(
            db.scalars(
                _ticket_query()
                .where(MasterSupportTicket.company_code == company_code)
                .order_by(MasterSupportTicket.last_message_at.desc())
            ).all()
        )


@router.post("/support/tickets/{ticket_id}/messages", response_model=MasterSupportTicketRead)
def add_customer_support_message(
    ticket_id: int,
    payload: MasterSupportReplyCreate,
    background_tasks: BackgroundTasks,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> MasterSupportTicket:
    token_data, user = _tenant_actor(credentials)
    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    with MasterSessionLocal() as db:
        ticket = db.scalar(
            _ticket_query().where(
                MasterSupportTicket.id == ticket_id,
                MasterSupportTicket.company_code == company_code,
            )
        )
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        if ticket.status == "fechado":
            ticket.status = "aberto"
            ticket.closed_at = None
        ticket.last_message_at = datetime.now(UTC)
        db.add(
            MasterSupportMessage(
                ticket_id=ticket.id,
                author_type="cliente",
                author_user_id=user.id,
                author_name=user.name,
                author_email=user.email,
                body=payload.body.strip(),
                attachment_url=payload.attachment_url,
                attachment_name=payload.attachment_name,
            )
        )
        db.commit()
        updated = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "message.created", updated)
    return updated


@router.get("/master/support/tickets", response_model=list[MasterSupportTicketRead])
def list_master_support_tickets(
    company_id: int | None = Query(default=None),
    ticket_status: str | None = Query(default=None, alias="status"),
    priority: str | None = Query(default=None),
    _: dict = Depends(require_master_permission("master:support")),
) -> list[MasterSupportTicket]:
    with MasterSessionLocal() as db:
        query = _ticket_query().order_by(MasterSupportTicket.last_message_at.desc())
        if company_id is not None:
            query = query.where(MasterSupportTicket.company_id == company_id)
        if ticket_status:
            query = query.where(MasterSupportTicket.status == ticket_status)
        if priority:
            query = query.where(MasterSupportTicket.priority == priority)
        return list(db.scalars(query).all())


@router.put("/master/support/tickets/{ticket_id}", response_model=MasterSupportTicketRead)
def update_master_support_ticket(
    ticket_id: int,
    payload: MasterSupportTicketUpdate,
    background_tasks: BackgroundTasks,
    _: dict = Depends(require_master_permission("master:support")),
) -> MasterSupportTicket:
    with MasterSessionLocal() as db:
        ticket = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket_id))
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        if payload.status is not None:
            ticket.status = _validate_choice(payload.status, VALID_STATUSES, "Status")
            _apply_status_dates(ticket, ticket.status)
        if payload.priority is not None:
            ticket.priority = _validate_choice(payload.priority, VALID_PRIORITIES, "Prioridade")
        if payload.customer_attachments_enabled is not None:
            ticket.customer_attachments_enabled = payload.customer_attachments_enabled
        if payload.assigned_master_user_id is not None:
            if db.get(MasterUser, payload.assigned_master_user_id) is None:
                raise HTTPException(status_code=404, detail="Funcionario master nao encontrado.")
            ticket.assigned_master_user_id = payload.assigned_master_user_id
        db.commit()
        updated = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "ticket.updated", updated)
    return updated


@router.post("/master/support/tickets/{ticket_id}/messages", response_model=MasterSupportTicketRead)
def add_master_support_message(
    ticket_id: int,
    payload: MasterSupportReplyCreate,
    background_tasks: BackgroundTasks,
    token_data: dict = Depends(require_master_permission("master:support")),
) -> MasterSupportTicket:
    master_user = _master_actor(token_data)
    with MasterSessionLocal() as db:
        ticket = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket_id))
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        now = datetime.now(UTC)
        if ticket.first_response_at is None:
            ticket.first_response_at = now
        if ticket.assigned_master_user_id is None:
            ticket.assigned_master_user_id = master_user.id
        if payload.status is not None:
            ticket.status = _validate_choice(payload.status, VALID_STATUSES, "Status")
            _apply_status_dates(ticket, ticket.status)
        elif ticket.status == "aberto":
            ticket.status = "em_analise"
        ticket.last_message_at = now
        db.add(
            MasterSupportMessage(
                ticket_id=ticket.id,
                author_type="master",
                author_user_id=master_user.id,
                author_name=master_user.name,
                author_email=master_user.email,
                body=payload.body.strip(),
                attachment_url=payload.attachment_url,
                attachment_name=payload.attachment_name,
            )
        )
        db.commit()
        updated = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "message.created", updated)
    return updated


@router.post("/support/tickets/{ticket_id}/attachments", response_model=MasterSupportTicketRead)
async def add_customer_support_attachment(
    ticket_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    body: str = Form(default=""),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> MasterSupportTicket:
    token_data, user = _tenant_actor(credentials)
    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    with MasterSessionLocal() as db:
        ticket = db.scalar(
            _ticket_query().where(
                MasterSupportTicket.id == ticket_id,
                MasterSupportTicket.company_code == company_code,
            )
        )
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        if not ticket.customer_attachments_enabled:
            raise HTTPException(status_code=403, detail="Anexos ainda nao foram liberados para este chamado.")
        attachment_url = await save_public_file(file, f"support-{company_code}")
        message_body = body.strip() or f"Arquivo enviado: {file.filename or 'anexo'}"
        ticket.last_message_at = datetime.now(UTC)
        db.add(
            MasterSupportMessage(
                ticket_id=ticket.id,
                author_type="cliente",
                author_user_id=user.id,
                author_name=user.name,
                author_email=user.email,
                body=message_body,
                attachment_url=attachment_url,
                attachment_name=file.filename or "anexo",
            )
        )
        db.commit()
        updated = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "message.created", updated)
    return updated


@router.post("/master/support/tickets/{ticket_id}/attachments", response_model=MasterSupportTicketRead)
async def add_master_support_attachment(
    ticket_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    body: str = Form(default=""),
    token_data: dict = Depends(require_master_permission("master:support")),
) -> MasterSupportTicket:
    master_user = _master_actor(token_data)
    with MasterSessionLocal() as db:
        ticket = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket_id))
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        now = datetime.now(UTC)
        if ticket.first_response_at is None:
            ticket.first_response_at = now
        if ticket.assigned_master_user_id is None:
            ticket.assigned_master_user_id = master_user.id
        attachment_url = await save_public_file(file, f"support-{ticket.company_code}")
        ticket.last_message_at = now
        db.add(
            MasterSupportMessage(
                ticket_id=ticket.id,
                author_type="master",
                author_user_id=master_user.id,
                author_name=master_user.name,
                author_email=master_user.email,
                body=body.strip() or f"Arquivo enviado: {file.filename or 'anexo'}",
                attachment_url=attachment_url,
                attachment_name=file.filename or "anexo",
            )
        )
        db.commit()
        updated = db.scalar(_ticket_query().where(MasterSupportTicket.id == ticket.id))
    background_tasks.add_task(support_ws.broadcast_ticket, "message.created", updated)
    return updated


@router.websocket("/support/ws")
async def support_customer_ws(websocket: WebSocket, token: str) -> None:
    try:
        company_code = _company_code_from_ws_token(token)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await support_ws.connect_company(company_code, websocket)
    await _ws_loop(websocket, company_code=company_code, is_master=False)


@router.websocket("/master/support/ws")
async def support_master_ws(websocket: WebSocket, token: str) -> None:
    try:
        _master_actor_with_permission(token)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await support_ws.connect_master(websocket)
    await _ws_loop(websocket, company_code=None, is_master=True)

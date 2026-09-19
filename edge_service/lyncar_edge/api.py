from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
import hmac
import hashlib
import secrets
from uuid import uuid4

from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, model_validator

from .cloud import CloudClient
from .config import EdgeSettings, get_settings
from .database import EdgeDatabase
from .sync import SyncEngine
from .print_coordinator import PrintCoordinator
from .printers import installed_printers


def _canonical_pedeon_channel(value: object) -> str:
    """Map the legacy Salon label to the channel consumed by Edge/PDV."""
    return 'onsite_waiter' if str(value) == 'onsite_qr' else str(value)


def _pedeon_item_enabled_for(item: dict, channel: str) -> bool:
    channels = item.get('enabled_channels')
    if not isinstance(channels, list):
        # Older local caches did not persist channel metadata. Keep those
        # products visible until the next catalog refresh supplies it.
        return bool(item.get('available', True))
    canonical = _canonical_pedeon_channel(channel)
    return canonical in {_canonical_pedeon_channel(value) for value in channels}


def _compact_event_key(prefix: str, *parts: object) -> str:
    """Keep locally generated idempotency keys below the API limit."""
    material = '|'.join((prefix, *(str(part) for part in parts)))
    digest = hashlib.sha256(material.encode('utf-8')).hexdigest()
    return f'{prefix}:{digest}'


def _normalize_event_key(
    prefix: str,
    supplied: str | None,
    *parts: object,
    max_length: int = 120,
) -> str:
    """Keep legacy client keys stable while enforcing the cloud limit."""
    raw = supplied.strip() if supplied else ""
    if raw and len(raw) <= max_length:
        return raw
    return _compact_event_key(prefix, raw, *parts)


class OrderTransitionRequest(BaseModel):
    status: str = Field(
        pattern=r"^(accepted|in_preparation|ready|out_for_delivery|completed|cancelled)$"
    )
    idempotency_key: str | None = Field(default=None, min_length=16, max_length=140)


class PrintResultRequest(BaseModel):
    status: str = Field(pattern=r"^(printed|failed)$")
    error: str | None = Field(default=None, max_length=1000)


class PairTerminalRequest(BaseModel):
    terminal_key: str | None = Field(default=None, min_length=16, max_length=180)
    pairing_code: str | None = Field(default=None, min_length=6, max_length=32)

    @model_validator(mode="after")
    def require_pairing_code(self):
        if not self.pairing_code and not self.terminal_key:
            raise ValueError("Informe o código exibido pelo Edge.")
        return self


class LoginTerminalRequest(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=6, max_length=128)
    terminal_id: int | None = Field(default=None, ge=1)


class WaiterLoginRequest(BaseModel):
    code: str = Field(min_length=2, max_length=30)
    pin: str = Field(min_length=4, max_length=30)


class StaffModifierSelection(BaseModel):
    option_id: int = Field(ge=1)
    quantity: float = Field(default=1, gt=0, le=50)


class StaffOrderItem(BaseModel):
    product_id: int = Field(ge=1)
    quantity: float = Field(gt=0, le=999)
    customer_notes: str | None = Field(default=None, max_length=500)
    modifiers: list[StaffModifierSelection] = Field(default_factory=list, max_length=100)


class StaffOrderCreateRequest(BaseModel):
    idempotency_key: str | None = Field(default=None, min_length=16, max_length=100)
    source_channel: str = Field(default="onsite_waiter", pattern=r"^(onsite_waiter|pdv_counter)$")
    table_label: str | None = Field(default=None, max_length=80)
    command_label: str | None = Field(default=None, max_length=80)
    customer_name: str = Field(default="Consumidor no local", min_length=2, max_length=180)
    customer_notes: str | None = Field(default=None, max_length=1000)
    items: list[StaffOrderItem] = Field(min_length=1, max_length=100)


class OrderCheckoutRequest(BaseModel):
    idempotency_key: str | None = Field(default=None, min_length=16, max_length=120)
    payment_method: str = Field(pattern=r"^(dinheiro|pix|debito|credito)$")
    amount_paid: float = Field(gt=0)
    authorization_code: str | None = Field(default=None, max_length=80)


class OperatorAuthorizationRequest(BaseModel):
    code: str = Field(min_length=1, max_length=30)
    pin: str = Field(min_length=1, max_length=30)


class CashSessionOpenRequest(BaseModel):
    cash_register_number: str = Field(min_length=1, max_length=10)
    opening_amount: float = Field(default=0, ge=0)
    operator_id: int = Field(ge=0)
    operator_name: str = Field(min_length=2, max_length=150)
    operator_type: str = Field(default="erp_owner", pattern=r"^(erp_owner|pedeon_operator)$")


class CashSessionCloseRequest(OperatorAuthorizationRequest):
    counted_cash_amount: float = Field(ge=0)
    notes: str | None = Field(default=None, max_length=1000)


class PrinterBindingRequest(BaseModel):
    logical_key: str = Field(pattern=r"^(cashier|station:[a-z0-9_-]{2,60})$")
    logical_name: str = Field(min_length=2, max_length=120)
    printer_name: str = Field(min_length=1, max_length=260)
    copies: int = Field(default=1, ge=1, le=5)
    auto_print: bool = True


class PrinterTestRequest(BaseModel):
    printer_name: str = Field(min_length=1, max_length=260)
    logical_name: str = Field(default="Teste", min_length=2, max_length=120)


def build_app(
    settings: EdgeSettings | None = None, *, start_background_sync: bool = True
) -> FastAPI:
    config = settings or get_settings()
    database = EdgeDatabase(config.database_path)
    cloud = CloudClient(config)
    engine = SyncEngine(config, database, cloud)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        database.migrate()
        if start_background_sync and config.configured:
            engine.start()
        yield
        if start_background_sync and engine._thread:
            engine.stop()

    app = FastAPI(title="Lyncar Edge", version="0.1.0", lifespan=lifespan)
    # O terminal Web do salão é servido na rede local e conversa diretamente
    # com o Edge. Não há cookies: a autorização continua sendo feita pelo
    # token local do terminal enviado em cabeçalho.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST", "PUT", "OPTIONS"],
        allow_headers=["Content-Type", "X-Lyncar-Edge-Key", "X-Lyncar-Edge-Token", "X-Lyncar-Waiter-Token"],
    )
    app.state.settings = config
    app.state.database = database
    app.state.sync_engine = engine

    def authorize(x_lyncar_edge_key: str = Header(default="")) -> None:
        if not hmac.compare_digest(x_lyncar_edge_key, config.lan_key):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Terminal local não pareado com o Lyncar Edge.",
            )

    def paired_terminal(x_lyncar_edge_token: str = Header(default="")) -> dict:
        token_hash = hashlib.sha256(x_lyncar_edge_token.encode("utf-8")).hexdigest()
        terminal = database.terminal_by_token_hash(token_hash)
        if terminal is None:
            terminal = database.staff_terminal_by_token_hash(token_hash)
        if terminal is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Terminal local não pareado ou revogado.",
            )
        return terminal

    def salon_session(x_lyncar_waiter_token: str = Header(default="")) -> dict:
        token_hash = hashlib.sha256(x_lyncar_waiter_token.encode("utf-8")).hexdigest()
        waiter = database.waiter_by_token_hash(token_hash)
        if waiter is None:
            raise HTTPException(status_code=401, detail="Sessão do garçom expirada ou revogada.")
        return waiter

    def staff_session(
        x_lyncar_edge_token: str = Header(default=""),
        x_lyncar_waiter_token: str = Header(default=""),
    ) -> dict:
        if x_lyncar_waiter_token:
            return salon_session(x_lyncar_waiter_token)
        return paired_terminal(x_lyncar_edge_token)

    def require_capability(capability: str):
        def dependency(terminal: dict = Depends(paired_terminal)) -> dict:
            if capability not in terminal["capabilities"]:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Terminal sem capacidade local: {capability}.",
                )
            return terminal

        return dependency

    def require_staff_capability(capability: str):
        def dependency(session: dict = Depends(staff_session)) -> dict:
            if capability not in session["capabilities"]:
                raise HTTPException(status_code=403, detail=f"Sessão sem capacidade local: {capability}.")
            return session
        return dependency

    @app.get("/.well-known/lyncar-edge")
    def discovery() -> dict:
        pairing_code = config.ensure_pairing_code()
        return {
            "service": "lyncar-edge",
            "protocol_version": 1,
            "node_key": config.node_key,
            "port": config.bind_port,
            "pairing_required": True,
            "pairing_code": pairing_code,
        }

    @app.get("/health")
    def health() -> dict:
        return {
            "status": "ok" if config.configured else "setup_required",
            "service": "lyncar-edge",
            "cloud": database.state("cloud.status", "starting"),
            "catalog_cursor": int(database.state("cursor.catalog", "0")),
            "order_cursor": int(database.state("cursor.orders", "0")),
            "last_error": database.state("cloud.last_error") or None,
            "server_time": datetime.now(timezone.utc).isoformat(),
            "pairing_code": config.ensure_pairing_code(),
        }

    @app.get("/v1/catalog/products")
    def products(
        limit: int = Query(default=100, ge=1, le=500),
        offset: int = Query(default=0, ge=0),
        _: dict = Depends(require_capability("view")),
    ) -> list[dict]:
        return database.list_entities("product", limit, offset)

    @app.get("/v1/pedeon/catalog")
    def pedeon_catalog(
        channel: str | None = Query(default=None),
        _: dict = Depends(require_staff_capability("view")),
    ) -> dict:
        stores = database.list_entities("catalog_store", 1, 0)
        raw_categories = database.list_entities("catalog_category", 500, 0)
        raw_items = database.list_entities("catalog_product", 500, 0)
        requested_channel = (
            _canonical_pedeon_channel(channel) if channel else None
        )
        items = (
            [
                item
                for item in raw_items
                if _pedeon_item_enabled_for(item, requested_channel)
            ]
            if requested_channel
            else raw_items
        )
        category_ids = {
            item.get('category_id')
            for item in items
            if item.get('category_id') is not None
        }
        return {
            "store": stores[0] if stores else None,
            "categories": [
                category
                for category in raw_categories
                if not requested_channel or category.get('id') in category_ids
            ],
            "items": items,
        }

    @app.get("/v1/printers")
    def printers(_: dict = Depends(require_capability("print"))) -> dict:
        return {
            "installed": installed_printers(),
            "bindings": database.printer_bindings(),
        }

    @app.put("/v1/printers/bindings")
    def bind_printer(
        payload: PrinterBindingRequest,
        _: dict = Depends(require_capability("print")),
    ) -> dict:
        if payload.printer_name not in installed_printers():
            raise HTTPException(status_code=409, detail="Impressora não encontrada neste Windows.")
        return database.save_printer_binding(**payload.model_dump())

    @app.post("/v1/printers/test")
    def test_printer(
        payload: PrinterTestRequest,
        _: dict = Depends(require_capability("print")),
    ) -> dict:
        try:
            PrintCoordinator(database).test(payload.printer_name, payload.logical_name)
        except Exception as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        return {"printed": True}

    @app.post("/v1/printers/process")
    def process_print_queue(
        _: dict = Depends(require_capability("print")),
    ) -> dict:
        return PrintCoordinator(database).process()

    @app.post("/v1/pair")
    def pair_terminal(
        payload: PairTerminalRequest,
        x_lyncar_edge_key: str = Header(default=""),
    ) -> dict:
        pairing_valid = payload.pairing_code and hmac.compare_digest(
            payload.pairing_code.strip().upper(), config.ensure_pairing_code()
        )
        legacy_valid = payload.pairing_code is None and hmac.compare_digest(
            x_lyncar_edge_key, config.lan_key
        )
        if not pairing_valid and not legacy_valid:
            raise HTTPException(status_code=401, detail="Código de pareamento inválido ou expirado.")
        try:
            authorization = cloud.authorize_terminal(payload.terminal_key or config.terminal_key)
        except Exception as exc:
            raise HTTPException(status_code=403, detail="Pareamento não autorizado.") from exc
        local_token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(local_token.encode("utf-8")).hexdigest()
        database.save_paired_terminal(authorization, token_hash)
        if pairing_valid:
            config.pairing_code = ""
            config.persist()
        database.set_state(
            "session.user",
            __import__("json").dumps(login.get("user", {"email": payload.email})),
        )
        return {
            "terminal_id": authorization["terminal_id"],
            "device_label": authorization.get("device_label"),
            "capabilities": authorization.get("capabilities", []),
            "station_ids": authorization.get("station_ids", []),
            "local_token": local_token,
            "user": login.get("user", {"email": payload.email}),
        }

    @app.post("/v1/login")
    def login_terminal(payload: LoginTerminalRequest) -> dict:
        try:
            login, terminals = cloud.login_pedeon(payload.email, payload.password)
        except Exception as exc:
            if not config.configured:
                raise HTTPException(status_code=401, detail="E-mail ou senha inválidos, ou usuário sem acesso ao PedeOn.") from exc
            try:
                operator = database.authorize_pedeon_operator(payload.email, payload.password)
                authorization = cloud.authorize_terminal(config.terminal_key)
            except Exception as operator_exc:
                raise HTTPException(status_code=401, detail="E-mail ou senha inválidos, ou usuário sem acesso ao PedeOn.") from operator_exc
            local_token = secrets.token_urlsafe(32)
            database.save_staff_session(
                token_hash=hashlib.sha256(local_token.encode("utf-8")).hexdigest(),
                terminal_id=int(authorization["terminal_id"]), user_email=payload.email,
                user_name=str(operator["name"]), operator_id=int(operator["id"]),
                capabilities=authorization.get("capabilities", []),
            )
            return {
                "selection_required": False, "company_name": "PedeOn",
                "terminal_id": authorization["terminal_id"],
                "device_label": authorization.get("device_label"),
                "capabilities": authorization.get("capabilities", []),
                "station_ids": authorization.get("station_ids", []),
                "local_token": local_token,
                "user": {"id": operator["id"], "name": operator["name"], "email": payload.email, "type": "pedeon_operator"},
            }
        if not terminals:
            raise HTTPException(
                status_code=403,
                detail=(
                    "Nenhum PDV PedeOn está liberado para esta empresa. "
                    "Libere um terminal em PedeOn > PDVs autorizados."
                ),
            )
        selected = None
        if payload.terminal_id is not None:
            selected = next(
                (item for item in terminals if int(item["id"]) == payload.terminal_id),
                None,
            )
            if selected is None:
                raise HTTPException(status_code=403, detail="Terminal não autorizado.")
        elif len(terminals) == 1:
            selected = terminals[0]
        else:
            return {
                "selection_required": True,
                "company_name": login.get("company_name"),
                "terminals": [
                    {
                        "id": item["id"],
                        "cash_register_number": item["cash_register_number"],
                        "device_label": item.get("device_label"),
                    }
                    for item in terminals
                ],
            }
        if not config.configured:
            config.access_token = str(login["access_token"])
            config.terminal_key = str(selected["terminal_key"])
            config.node_key = secrets.token_urlsafe(32)
            config.lan_key = secrets.token_urlsafe(32)
            config.persist()
            cloud.set_access_token(config.access_token)
        try:
            # Register the Edge node before asking the API to authorize its PDV.
            # This is the missing step in the first-access flow.
            cloud.register()
            authorization = cloud.authorize_terminal(selected["terminal_key"])
        except Exception as exc:
            raise HTTPException(status_code=403, detail="Terminal PedeOn não autorizado.") from exc
        local_token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(local_token.encode("utf-8")).hexdigest()
        database.save_paired_terminal(authorization, token_hash)
        if start_background_sync and config.configured:
            engine.start()
        return {
            "selection_required": False,
            "company_name": login.get("company_name"),
            "terminal_id": authorization["terminal_id"],
            "device_label": authorization.get("device_label"),
            "capabilities": authorization.get("capabilities", []),
            "station_ids": authorization.get("station_ids", []),
            "local_token": local_token,
        }

    @app.post("/v1/salon/login")
    def login_salon(payload: WaiterLoginRequest) -> dict:
        try:
            waiter = database.authorize_waiter(payload.code, payload.pin)
            authorization = cloud.authorize_terminal(config.terminal_key)
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(status_code=503, detail="Não foi possível validar o terminal de salão.") from exc
        if "view" not in authorization.get("capabilities", []) or "accept" not in authorization.get("capabilities", []):
            raise HTTPException(status_code=403, detail="O terminal Edge não está liberado para pedidos de salão.")
        local_token = secrets.token_urlsafe(32)
        database.save_waiter_session(
            token_hash=hashlib.sha256(local_token.encode("utf-8")).hexdigest(),
            terminal_id=int(authorization["terminal_id"]),
            user_email=str(waiter["code"]),
            user_name=str(waiter["name"]),
        )
        return {"local_token": local_token, "user_name": waiter["name"], "terminal_id": authorization["terminal_id"]}

    @app.get("/v1/terminal/session")
    def terminal_session(terminal: dict = Depends(paired_terminal)) -> dict:
        try:
            user = __import__("json").loads(database.state("session.user", "{}"))
        except ValueError:
            user = {}
        return {
            "terminal_id": terminal["terminal_id"],
            "device_label": terminal["device_label"],
            "capabilities": terminal["capabilities"],
            "station_ids": terminal["station_ids"],
            "notification_mode": terminal["notification_mode"],
            "user": user,
        }

    @app.get("/v1/clients")
    def clients(
        limit: int = Query(default=100, ge=1, le=500),
        offset: int = Query(default=0, ge=0),
        _: dict = Depends(require_capability("view")),
    ) -> list[dict]:
        return database.list_entities("client", limit, offset)

    @app.post("/v1/operators/authorize")
    def authorize_operator(
        payload: OperatorAuthorizationRequest,
        _: dict = Depends(require_capability("checkout")),
    ) -> dict:
        try:
            return database.authorize_operator(
                payload.code, payload.pin, require_open_cash=False
            )
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc

    @app.get("/v1/cash-sessions/open")
    def get_open_cash_session(
        terminal: dict = Depends(require_capability("checkout")),
    ) -> dict | None:
        return database.open_cash_session_for_terminal(int(terminal["terminal_id"]))

    @app.post("/v1/cash-sessions/open", status_code=201)
    def open_cash_session(
        payload: CashSessionOpenRequest,
        terminal: dict = Depends(require_capability("checkout")),
    ) -> dict:
        try:
            if payload.operator_type == "erp_owner":
                operator = {
                    "id": payload.operator_id,
                    "name": payload.operator_name,
                }
            else:
                operator = database.authorize_operator(
                    payload.operator_name, "", require_open_cash=True
                )
            return database.open_cash_session(
                local_key=f"cash:{config.node_key}:{uuid4()}",
                terminal_id=int(terminal["terminal_id"]),
                cash_register_number=payload.cash_register_number.strip(),
                operator=operator,
                opening_amount=payload.opening_amount,
                operator_type=payload.operator_type,
            )
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc

    @app.post("/v1/cash-sessions/close", status_code=202)
    def close_cash_session(
        payload: CashSessionCloseRequest,
        terminal: dict = Depends(require_capability("checkout")),
    ) -> dict:
        try:
            fiscal = database.authorize_operator(
                payload.code,
                payload.pin,
                require_open_cash=False,
                require_fiscal=True,
            )
            return database.close_cash_session(
                terminal_id=int(terminal["terminal_id"]),
                fiscal=fiscal,
                counted_cash_amount=payload.counted_cash_amount,
                notes=payload.notes,
            )
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.get("/v1/orders")
    def orders(
        limit: int = Query(default=100, ge=1, le=500),
        offset: int = Query(default=0, ge=0),
        _: dict = Depends(require_capability("view")),
    ) -> list[dict]:
        return database.list_entities("order", limit, offset)

    @app.get("/v1/sync/issues")
    def sync_issues(
        limit: int = Query(default=100, ge=1, le=500),
        _: dict = Depends(require_capability("view")),
    ) -> list[dict]:
        return database.outbox_issues(limit)

    @app.post("/v1/staff/orders", status_code=201)
    def create_staff_order(
        payload: StaffOrderCreateRequest,
        terminal: dict = Depends(require_staff_capability("accept")),
    ) -> dict:
        event_key = payload.idempotency_key or f"edge:{config.node_key}:{uuid4()}"
        try:
            return database.create_local_staff_order(
                event_key=event_key,
                terminal_id=int(terminal["terminal_id"]),
                source_channel=payload.source_channel,
                table_label=payload.table_label,
                command_label=payload.command_label,
                customer_name=payload.customer_name,
                customer_notes=payload.customer_notes,
                items=[item.model_dump() for item in payload.items],
                waiter_email=terminal.get("user_email"),
                waiter_name=terminal.get("user_name"),
            )
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.post("/v1/orders/{order_id}/checkout")
    def checkout_order(
        order_id: str,
        payload: OrderCheckoutRequest,
        terminal: dict = Depends(require_capability("checkout")),
    ) -> dict:
        # A checkout key is persisted in the cloud outbox and must stay within
        # the API's 120-character limit. The order id and Edge node are already
        # represented by the request context, so a UUID is sufficient here.
        event_key = payload.idempotency_key or f"checkout:{uuid4()}"
        try:
            cash_session = database.open_cash_session_for_terminal(
                int(terminal["terminal_id"])
            )
            if cash_session is None:
                raise ValueError("Abra o caixa antes de receber pedidos.")
            return database.enqueue_order_checkout(
                event_key=event_key,
                order_id=order_id,
                terminal_id=int(terminal["terminal_id"]),
                payment_method=payload.payment_method,
                amount_paid=payload.amount_paid,
                authorization_code=payload.authorization_code,
                cash_session=cash_session,
            )
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.post("/v1/orders/{order_id}/transition")
    def transition(
        order_id: str,
        payload: OrderTransitionRequest,
        terminal: dict = Depends(paired_terminal),
    ) -> dict:
        required = {
            "accepted": "accept",
            "in_preparation": "prepare",
            "ready": "prepare",
            "out_for_delivery": "dispatch",
            "completed": "dispatch",
            "cancelled": "cancel",
        }[payload.status]
        if required not in terminal["capabilities"]:
            raise HTTPException(status_code=403, detail=f"Terminal sem capacidade: {required}.")
        event_key = payload.idempotency_key or f"edge:{config.node_key}:{uuid4()}"
        try:
            database.enqueue_order_transition(event_key, order_id, payload.status)
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"accepted": True, "event_key": event_key, "queued": True}

    @app.get("/v1/print-jobs/claim")
    def claim_print_jobs(
        limit: int = Query(default=10, ge=1, le=25),
        terminal: dict = Depends(require_capability("print")),
    ) -> list[dict]:
        return database.claim_print_jobs(
            str(terminal["terminal_id"]), limit, terminal["station_ids"]
        )

    @app.post("/v1/print-jobs/{job_id}/finish")
    def finish_print_job(
        job_id: int,
        payload: PrintResultRequest,
        terminal: dict = Depends(require_capability("print")),
    ) -> dict:
        try:
            return database.finish_local_print_job(
                job_id, str(terminal["terminal_id"]), payload.status, payload.error
            )
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.post("/v1/sync", dependencies=[Depends(authorize)])
    def synchronize(full: bool = False) -> dict:
        result = engine.sync_once(force_snapshot=full)
        return {
            "online": result.online,
            "catalog_cursor": result.catalog_cursor,
            "order_cursor": result.order_cursor,
            "last_error": result.last_error,
        }

    return app


app = build_app()

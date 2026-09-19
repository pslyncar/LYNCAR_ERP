import asyncio
from collections import defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from jwt import ExpiredSignatureError, InvalidTokenError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission
from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.client import Client
from app.models.pdv_operator import PdvOperator
from app.models.pdv_sync_event import PdvSyncEvent
from app.models.product import Product
from app.models.user import User
from app.schemas.client import ClientRead
from app.schemas.product import ProductRead
from app.services.tenancy import (
    normalize_company_code,
    require_active_company,
    session_for_company,
)

router = APIRouter()


def _current_cursor(db: Session) -> int:
    return int(db.scalar(select(func.max(PdvSyncEvent.id))) or 0)


def _product_json(product: Product) -> dict:
    return ProductRead.model_validate(product).model_dump(mode="json")


def _client_json(client: Client) -> dict:
    return ClientRead.model_validate(client).model_dump(mode="json")


def _operator_json(operator: PdvOperator) -> dict:
    """Return the minimum credential material required by a paired Edge.

    The Edge must verify waiter PINs while offline, so it needs the password
    hash. The endpoint is protected by the existing PDV sync permissions and
    the hash is never returned by the public/operator-management endpoints.
    """
    return {
        "id": operator.id,
        "name": operator.name,
        "code": operator.code,
        "pin_hash": operator.pin_hash,
        "role": operator.role,
        "can_open_cash": operator.can_open_cash,
        "can_authorize_withdrawal": operator.can_authorize_withdrawal,
        "can_authorize_cancel": operator.can_authorize_cancel,
        "can_authorize_discount": operator.can_authorize_discount,
        "active": operator.active,
        "notes": operator.notes,
    }


def _is_legacy_pdv_operator(operator: PdvOperator) -> bool:
    """Keep PedeOn identities out of the legacy PDV synchronization feed."""
    return operator.role not in {"waiter", "pedeon_operator"}


def _empty_batch(cursor: int, *, reset_required: bool = False) -> dict:
    return {
        "cursor": cursor,
        "server_time": datetime.now(timezone.utc).isoformat(),
        "products": [],
        "clients": [],
        "operators": [],
        "pedeon_waiters": [],
        "pedeon_operators": [],
        "legacy_deleted_operator_ids": [],
        "deleted_product_ids": [],
        "deleted_client_ids": [],
        "reset_required": reset_required,
        "has_more": False,
    }


@router.get("/sync/snapshot")
def pdv_sync_snapshot(
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("sales:create", "sales:manual", "products:view")
    ),
) -> dict:
    del current_user
    products = list(
        db.scalars(
            select(Product).where(Product.active.is_(True)).order_by(Product.name)
        ).all()
    )
    clients = list(db.scalars(select(Client).order_by(Client.name)).all())
    operators = list(
        db.scalars(
            select(PdvOperator)
            .where(PdvOperator.active.is_(True))
            .order_by(PdvOperator.name)
        ).all()
    )
    result = _empty_batch(_current_cursor(db))
    result["products"] = [_product_json(product) for product in products]
    result["clients"] = [_client_json(client) for client in clients]
    result["operators"] = [
        _operator_json(operator)
        for operator in operators
        if _is_legacy_pdv_operator(operator)
    ]
    result["pedeon_waiters"] = [
        _operator_json(operator) for operator in operators if operator.role == "waiter"
    ]
    result["pedeon_operators"] = [
        _operator_json(operator)
        for operator in operators
        if operator.role == "pedeon_operator"
    ]
    result["legacy_deleted_operator_ids"] = [
        operator.id
        for operator in operators
        if not _is_legacy_pdv_operator(operator)
    ]
    return result


@router.get("/sync/changes")
def pdv_sync_changes(
    after: int = Query(default=0, ge=0),
    limit: int = Query(default=500, ge=1, le=2000),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("sales:create", "sales:manual", "products:view")
    ),
) -> dict:
    del current_user
    current_cursor = _current_cursor(db)
    minimum_cursor = int(db.scalar(select(func.min(PdvSyncEvent.id))) or 0)
    if after > current_cursor or (
        minimum_cursor > 0 and after > 0 and after < minimum_cursor - 1
    ):
        return _empty_batch(current_cursor, reset_required=True)

    events = list(
        db.scalars(
            select(PdvSyncEvent)
            .where(PdvSyncEvent.id > after)
            .order_by(PdvSyncEvent.id)
            .limit(limit)
        ).all()
    )
    if not events:
        return _empty_batch(current_cursor)

    latest: dict[tuple[str, int], PdvSyncEvent] = {}
    for item in events:
        latest[(item.entity_type, item.entity_id)] = item

    upserts: dict[str, list[int]] = defaultdict(list)
    deletes: dict[str, list[int]] = defaultdict(list)
    for (entity_type, entity_id), item in latest.items():
        target = deletes if item.operation == "delete" else upserts
        target[entity_type].append(entity_id)

    products = (
        list(
            db.scalars(
                select(Product).where(Product.id.in_(upserts["product"]))
            ).all()
        )
        if upserts["product"]
        else []
    )
    clients = (
        list(db.scalars(select(Client).where(Client.id.in_(upserts["client"]))).all())
        if upserts["client"]
        else []
    )
    operators = (
        list(
            db.scalars(
                select(PdvOperator).where(PdvOperator.id.in_(upserts["operator"]))
            ).all()
        )
        if upserts["operator"]
        else []
    )
    deleted_operator_ids = list(deletes["operator"])
    active_operators: list[PdvOperator] = []
    for operator in operators:
        if operator.active:
            active_operators.append(operator)
        else:
            deleted_operator_ids.append(operator.id)
    deleted_product_ids = list(deletes["product"])
    active_products: list[Product] = []
    for product in products:
        if product.active:
            active_products.append(product)
        else:
            deleted_product_ids.append(product.id)

    result = _empty_batch(events[-1].id)
    result["has_more"] = events[-1].id < current_cursor
    result["products"] = [_product_json(product) for product in active_products]
    result["clients"] = [_client_json(client) for client in clients]
    result["operators"] = [
        _operator_json(operator)
        for operator in active_operators
        if _is_legacy_pdv_operator(operator)
    ]
    result["pedeon_waiters"] = [
        _operator_json(operator)
        for operator in active_operators
        if operator.role == "waiter"
    ]
    result["pedeon_operators"] = [
        _operator_json(operator)
        for operator in active_operators
        if operator.role == "pedeon_operator"
    ]
    result["legacy_deleted_operator_ids"] = [
        operator.id
        for operator in active_operators
        if not _is_legacy_pdv_operator(operator)
    ]
    result["deleted_product_ids"] = sorted(set(deleted_product_ids))
    result["deleted_client_ids"] = sorted(set(deletes["client"]))
    result["deleted_operator_ids"] = sorted(set(deleted_operator_ids))
    return result


def _latest_cursor_for_company(company_code: str) -> int:
    with session_for_company(company_code) as db:
        return _current_cursor(db)


class _TenantSyncHub:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._last_cursor: dict[str, int] = {}

    async def connect(self, company_code: str, websocket: WebSocket) -> None:
        self._connections[company_code].add(websocket)
        cursor = await asyncio.to_thread(_latest_cursor_for_company, company_code)
        self._last_cursor[company_code] = max(
            cursor,
            self._last_cursor.get(company_code, 0),
        )
        await websocket.send_json({"type": "sync", "cursor": cursor})
        task = self._tasks.get(company_code)
        if task is None or task.done():
            self._tasks[company_code] = asyncio.create_task(self._watch(company_code))

    async def disconnect(self, company_code: str, websocket: WebSocket) -> None:
        sockets = self._connections.get(company_code)
        if sockets is None:
            return
        sockets.discard(websocket)
        if sockets:
            return
        self._connections.pop(company_code, None)
        task = self._tasks.pop(company_code, None)
        if task is not None:
            task.cancel()
        self._last_cursor.pop(company_code, None)

    async def _watch(self, company_code: str) -> None:
        try:
            while self._connections.get(company_code):
                await asyncio.sleep(2)
                cursor = await asyncio.to_thread(
                    _latest_cursor_for_company,
                    company_code,
                )
                if cursor <= self._last_cursor.get(company_code, 0):
                    continue
                self._last_cursor[company_code] = cursor
                stale: list[WebSocket] = []
                for socket in tuple(self._connections.get(company_code, ())):
                    try:
                        await socket.send_json({"type": "sync", "cursor": cursor})
                    except Exception:
                        stale.append(socket)
                for socket in stale:
                    await self.disconnect(company_code, socket)
        except asyncio.CancelledError:
            return


sync_hub = _TenantSyncHub()


@router.websocket("/sync/ws")
async def pdv_sync_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        authentication = await asyncio.wait_for(
            websocket.receive_json(),
            timeout=10,
        )
        if not isinstance(authentication, dict):
            raise ValueError("Autenticacao WebSocket invalida.")
        token = str(authentication.get("token") or "")
        payload = decode_access_token(token)
        company_code = normalize_company_code(str(payload["company_code"]))
        require_active_company(company_code)
        user_id = int(payload["sub"])
        with session_for_company(company_code) as db:
            user = db.get(User, user_id)
            if user is None or not user.active:
                raise ValueError("Usuario inativo.")
    except (
        ExpiredSignatureError,
        InvalidTokenError,
        KeyError,
        LookupError,
        TypeError,
        ValueError,
        asyncio.TimeoutError,
        WebSocketDisconnect,
    ):
        await websocket.close(code=1008)
        return

    await sync_hub.connect(company_code, websocket)
    try:
        while True:
            message = await websocket.receive_text()
            if message == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    finally:
        await sync_hub.disconnect(company_code, websocket)

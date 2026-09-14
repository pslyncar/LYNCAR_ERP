from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.pdv_terminal import PdvTerminal
from app.modules.pedeon.application.edge_schemas import (
    EDGE_CAPABILITIES,
    EDGE_PROTOCOL_VERSION,
    EdgeHeartbeatRequest,
    EdgeNodeRead,
    EdgeRegisterRequest,
    EdgeTerminalAuthorizationRead,
    EdgeTerminalAuthorizeRequest,
)
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnEdgeNode,
    PedeOnStore,
    PedeOnTerminalPermission,
)
from app.modules.pedeon.application.staff_schemas import EdgeOrderCheckout, EdgeStaffOrderCreate


class PedeOnEdgeService:
    def __init__(self, db: Session):
        self.db = db

    def register(self, payload: EdgeRegisterRequest, client_ip: str | None) -> EdgeNodeRead:
        if payload.protocol_version != EDGE_PROTOCOL_VERSION:
            raise ValueError(
                f"Protocolo Edge incompatível. Esperado {EDGE_PROTOCOL_VERSION}."
            )
        terminal, store = self._authorized_terminal(payload.terminal_key)
        now = datetime.now(timezone.utc)
        node = self.db.scalar(
            select(PedeOnEdgeNode)
            .where(PedeOnEdgeNode.store_id == store.id)
            .with_for_update()
        )
        if node is None:
            node = PedeOnEdgeNode(
                store_id=store.id,
                pdv_terminal_id=terminal.id,
                node_key=payload.node_key,
                registered_at=now,
                cursors={},
                capabilities=list(EDGE_CAPABILITIES),
            )
            self.db.add(node)
        else:
            node.pdv_terminal_id = terminal.id
            node.node_key = payload.node_key
        node.device_label = payload.device_label
        node.app_version = payload.app_version
        node.protocol_version = payload.protocol_version
        node.status = "online"
        node.last_ip = client_ip
        node.last_error = None
        node.last_seen_at = now
        node.updated_at = now
        terminal.last_seen_at = now
        terminal.updated_at = now
        self.db.commit()
        self.db.refresh(node)
        return self._read(node, terminal.id, store.public_slug, now)

    def heartbeat(
        self,
        node_key: str,
        payload: EdgeHeartbeatRequest,
        client_ip: str | None,
    ) -> EdgeNodeRead:
        terminal, store = self._authorized_terminal(payload.terminal_key)
        node = self.db.scalar(
            select(PedeOnEdgeNode).where(
                PedeOnEdgeNode.store_id == store.id,
                PedeOnEdgeNode.node_key == node_key,
                PedeOnEdgeNode.pdv_terminal_id == terminal.id,
            )
        )
        if node is None:
            raise LookupError("Edge não registrado para este estabelecimento.")
        now = datetime.now(timezone.utc)
        current = dict(node.cursors or {})
        for stream, cursor in payload.cursors.items():
            # Heartbeats can arrive from a previously cached Edge database.
            # Cursor state is monotonic on the server: an older heartbeat must
            # never make a newer acknowledged position go backwards, but it
            # also must not turn an otherwise healthy sync into an error.
            current[stream] = max(cursor, int(current.get(stream, 0)))
        node.cursors = current
        node.status = "degraded" if payload.last_error else "online"
        node.last_error = payload.last_error
        node.last_ip = client_ip
        node.last_seen_at = now
        node.updated_at = now
        terminal.last_seen_at = now
        terminal.updated_at = now
        self.db.commit()
        return self._read(node, terminal.id, store.public_slug, now)

    def authorize_terminal(
        self, payload: EdgeTerminalAuthorizeRequest
    ) -> EdgeTerminalAuthorizationRead:
        edge_terminal, store = self._authorized_terminal(payload.edge_terminal_key)
        edge = self.db.scalar(
            select(PedeOnEdgeNode).where(
                PedeOnEdgeNode.store_id == store.id,
                PedeOnEdgeNode.node_key == payload.edge_node_key,
                PedeOnEdgeNode.pdv_terminal_id == edge_terminal.id,
            )
        )
        if edge is None:
            raise PermissionError("Edge principal não registrado.")
        terminal = self.db.scalar(
            select(PdvTerminal).where(
                PdvTerminal.terminal_key == payload.terminal_key.strip(),
                PdvTerminal.active.is_(True),
                PdvTerminal.activation_status == "active",
            )
        )
        if terminal is None:
            raise PermissionError("Terminal local inválido ou bloqueado.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.store_id == store.id,
                PedeOnTerminalPermission.pdv_terminal_id == terminal.id,
                PedeOnTerminalPermission.enabled.is_(True),
            )
        )
        if permission is None:
            raise PermissionError("Terminal não liberado para esta loja PedeOn.")
        return EdgeTerminalAuthorizationRead(
            terminal_id=terminal.id,
            device_label=terminal.device_label or terminal.machine_name,
            capabilities=list(permission.capabilities or []),
            station_ids=[int(item) for item in (permission.station_ids or [])],
            notification_mode=permission.notification_mode,
            priority=permission.priority,
        )

    def authorize_staff_order(
        self, payload: EdgeStaffOrderCreate
    ) -> tuple[PedeOnStore, PdvTerminal]:
        edge_terminal, store = self._authorized_terminal(payload.edge_terminal_key)
        edge = self.db.scalar(
            select(PedeOnEdgeNode).where(
                PedeOnEdgeNode.store_id == store.id,
                PedeOnEdgeNode.node_key == payload.edge_node_key,
                PedeOnEdgeNode.pdv_terminal_id == edge_terminal.id,
            )
        )
        if edge is None:
            raise PermissionError("Edge principal não registrado.")
        terminal = self.db.get(PdvTerminal, payload.terminal_id)
        if terminal is None:
            raise PermissionError("Terminal local não autorizado para este estabelecimento.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.store_id == store.id,
                PedeOnTerminalPermission.pdv_terminal_id == payload.terminal_id,
                PedeOnTerminalPermission.enabled.is_(True),
            )
        )
        if terminal is None or not terminal.active or permission is None:
            raise PermissionError("Terminal local não autorizado para este estabelecimento.")
        if "accept" not in list(permission.capabilities or []):
            raise PermissionError("Terminal sem permissão para criar pedidos locais.")
        return store, terminal

    def authorize_catalog(self, terminal_key: str) -> PedeOnStore:
        """Resolve the store whose operational catalog may be copied to an Edge."""
        _terminal, store = self._authorized_terminal(terminal_key)
        return store

    def authorize_checkout(
        self, payload: EdgeOrderCheckout
    ) -> tuple[PedeOnStore, PdvTerminal]:
        edge_terminal, store = self._authorized_terminal(payload.edge_terminal_key)
        edge = self.db.scalar(
            select(PedeOnEdgeNode).where(
                PedeOnEdgeNode.store_id == store.id,
                PedeOnEdgeNode.node_key == payload.edge_node_key,
                PedeOnEdgeNode.pdv_terminal_id == edge_terminal.id,
            )
        )
        if edge is None:
            raise PermissionError("Edge principal não registrado.")
        terminal = self.db.get(PdvTerminal, payload.terminal_id)
        if terminal is None:
            raise PermissionError("Terminal local não autorizado para este estabelecimento.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.store_id == store.id,
                PedeOnTerminalPermission.pdv_terminal_id == terminal.id,
                PedeOnTerminalPermission.enabled.is_(True),
            )
        )
        if terminal is None or not terminal.active or permission is None:
            raise PermissionError("Terminal local não autorizado para este estabelecimento.")
        capabilities = list(permission.capabilities or []) if permission else []
        if "checkout" not in capabilities:
            raise PermissionError("Terminal sem permissão para receber e fechar pedidos.")
        return store, terminal

    def _authorized_terminal(self, terminal_key: str) -> tuple[PdvTerminal, PedeOnStore]:
        terminal = self.db.scalar(
            select(PdvTerminal).where(
                PdvTerminal.terminal_key == terminal_key.strip(),
                PdvTerminal.active.is_(True),
                PdvTerminal.activation_status == "active",
            )
        )
        if terminal is None:
            raise PermissionError("Terminal não ativado ou bloqueado.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.pdv_terminal_id == terminal.id,
                PedeOnTerminalPermission.enabled.is_(True),
            )
        )
        if permission is None:
            raise PermissionError("Terminal sem autorização para o PedeOn.")
        store = self.db.get(PedeOnStore, permission.store_id)
        if store is None:
            raise LookupError("Loja PedeOn não configurada.")
        return terminal, store

    @staticmethod
    def _read(
        node: PedeOnEdgeNode, terminal_id: int, public_slug: str, now: datetime
    ) -> EdgeNodeRead:
        return EdgeNodeRead(
            node_key=node.node_key,
            store_id=node.store_id,
            public_slug=public_slug,
            terminal_id=terminal_id,
            status=node.status,
            protocol_version=node.protocol_version,
            capabilities=list(node.capabilities or []),
            cursors={key: int(value) for key, value in (node.cursors or {}).items()},
            app_version=node.app_version,
            device_label=node.device_label,
            registered_at=node.registered_at,
            last_seen_at=node.last_seen_at,
            server_time=now,
        )

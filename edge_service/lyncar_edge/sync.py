from __future__ import annotations

from dataclasses import dataclass
import threading
import time

import requests

from .cloud import CloudClient
from .config import EdgeSettings
from .database import EdgeDatabase
from .print_coordinator import PrintCoordinator


@dataclass(frozen=True)
class SyncResult:
    online: bool
    catalog_cursor: int
    order_cursor: int
    last_error: str | None = None


class SyncEngine:
    def __init__(self, settings: EdgeSettings, database: EdgeDatabase, cloud: CloudClient):
        self.settings = settings
        self.database = database
        self.cloud = cloud
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run, name="lyncar-edge-sync", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=5)

    def sync_once(self, force_snapshot: bool = False) -> SyncResult:
        try:
            registration = self.cloud.register()
            self.database.set_state("store.public_slug", str(registration["public_slug"]))
            catalog = int(self.database.state("cursor.catalog", "0"))
            orders = int(self.database.state("cursor.orders", "0"))
            refresh_operational_catalog = (
                force_snapshot
                or self.database.state("pedeon.catalog.schema") != "channels-v1"
            )
            remote_catalog_revision = self.cloud.edge_catalog_revision()
            refresh_operational_catalog = refresh_operational_catalog or (
                remote_catalog_revision
                != int(self.database.state("pedeon.catalog.revision", "-1"))
            )
            if force_snapshot or not self.database.state("snapshot.completed"):
                snapshot = self.cloud.snapshot()
                self.database.replace_snapshot(
                    snapshot.get("products", []),
                    snapshot.get("clients", []),
                    snapshot.get("operators", []),
                    snapshot.get("pedeon_waiters", []),
                    snapshot.get("pedeon_operators", []),
                )
                catalog = int(snapshot.get("cursor", 0))
                self.database.set_state("cursor.catalog", str(catalog))
                self.database.set_state("snapshot.completed", "1")
                refresh_operational_catalog = True
            else:
                while True:
                    changes = self.cloud.changes(catalog)
                    if changes.get("reset_required"):
                        return self.sync_once(force_snapshot=True)
                    self.database.apply_changes(changes)
                    catalog = int(changes.get("cursor", catalog))
                    self.database.set_state("cursor.catalog", str(catalog))
                    if not changes.get("has_more"):
                        break
            if refresh_operational_catalog:
                operational_catalog = self.cloud.edge_catalog()
                self.database.replace_pedeon_catalog(operational_catalog)
                self.database.set_state("pedeon.catalog.schema", "channels-v1")
                self.database.set_state(
                    "pedeon.catalog.revision",
                    str(operational_catalog.get("revision", remote_catalog_revision)),
                )
            while True:
                feed = self.cloud.order_feed(orders)
                events = feed.get("events", [])
                self.database.store_order_events(events)
                changed_ids = list(
                    dict.fromkeys(str(event["order_id"]) for event in events)
                )
                if changed_ids:
                    self.database.store_order_details(
                        [self.cloud.order_detail(public_id) for public_id in changed_ids]
                    )
                orders = int(feed.get("next_cursor", orders))
                self.database.set_state("cursor.orders", str(orders))
                if not feed.get("has_more"):
                    break
            self.database.store_print_jobs(self.cloud.claim_print_jobs())
            PrintCoordinator(self.database).process()
            self._flush_outbox()
            self.cloud.heartbeat(
                {"catalog": catalog, "orders": orders, "outbox": self._outbox_cursor()},
                None,
            )
            self.database.set_state("cloud.status", "online")
            self.database.set_state("cloud.last_error", "")
            return SyncResult(True, catalog, orders)
        except (requests.RequestException, LookupError, RuntimeError, ValueError) as exc:
            message = str(exc)[:1000]
            self.database.set_state("cloud.status", "offline")
            self.database.set_state("cloud.last_error", message)
            return SyncResult(
                False,
                int(self.database.state("cursor.catalog", "0")),
                int(self.database.state("cursor.orders", "0")),
                message,
            )

    def _flush_outbox(self) -> None:
        for event in self.database.ready_outbox():
            attempts = int(event["attempts"]) + 1
            try:
                if event["event_type"] == "order.transition":
                    order = self.cloud.transition_order(
                        str(event["aggregate_id"]), str(event["payload"]["status"])
                    )
                    order["local_sync_pending"] = False
                    self.database.store_order_details([order])
                elif event["event_type"] == "order.create":
                    order = self.cloud.create_staff_order(event["payload"])
                    self.database.replace_local_order(str(event["aggregate_id"]), order)
                elif event["event_type"] == "order.checkout":
                    if not event["payload"].get("cash_session_id"):
                        raise LookupError("Abertura do caixa ainda aguardando sincronização.")
                    self.cloud.checkout_order(str(event["aggregate_id"]), event["payload"])
                    order = self.cloud.order_detail(str(event["aggregate_id"]))
                    order["local_sync_pending"] = False
                    self.database.store_order_details([order])
                elif event["event_type"] == "cash.open":
                    result = self.cloud.open_cash_session(event["payload"])
                    self.database.bind_cloud_cash_session(
                        str(event["aggregate_id"]), int(result["id"])
                    )
                elif event["event_type"] == "cash.close":
                    if not event["payload"].get("cash_session_id"):
                        raise LookupError("Abertura do caixa ainda aguardando sincronização.")
                    self.cloud.close_cash_session(event["payload"])
                elif event["event_type"] == "print.result":
                    self.cloud.finish_print_job(
                        int(event["aggregate_id"]),
                        str(event["payload"]["status"]),
                        event["payload"].get("error"),
                    )
                else:
                    raise ValueError(f"Evento local nao suportado: {event['event_type']}")
                self.database.mark_sent(int(event["id"]))
            except requests.HTTPError as exc:
                code = exc.response.status_code if exc.response is not None else 0
                if 400 <= code < 500 and code not in {408, 429}:
                    self.database.mark_blocked(int(event["id"]), attempts, str(exc))
                else:
                    self.database.mark_failed(int(event["id"]), attempts, str(exc))
            except (requests.RequestException, LookupError, ValueError) as exc:
                self.database.mark_failed(int(event["id"]), attempts, str(exc))

    def _outbox_cursor(self) -> int:
        cursor = self.database.sent_outbox_cursor()
        self.database.set_state("cursor.outbox", str(cursor))
        return cursor

    def _run(self) -> None:
        while not self._stop.is_set():
            self.sync_once()
            self._stop.wait(self.settings.sync_interval_seconds)

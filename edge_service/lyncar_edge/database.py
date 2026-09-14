from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import base64
import hashlib
import hmac
import json
from pathlib import Path
import sqlite3
from typing import Iterator

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError


SCHEMA_VERSION = 8
_ARGON2_PASSWORD_HASHER = PasswordHasher()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _verify_password(password: str, stored_hash: str) -> bool:
    if stored_hash.startswith("$argon2"):
        try:
            return _ARGON2_PASSWORD_HASHER.verify(stored_hash, password)
        except (InvalidHashError, VerificationError, VerifyMismatchError):
            return False
    try:
        prefix, iterations_text, salt_b64, hash_b64 = stored_hash.split("$", 3)
        if prefix != "pbkdf2_sha256":
            return False
        expected = base64.b64decode(hash_b64.encode("ascii"))
        calculated = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            base64.b64decode(salt_b64.encode("ascii")),
            int(iterations_text),
            dklen=len(expected),
        )
        return hmac.compare_digest(calculated, expected)
    except (TypeError, ValueError):
        return False


class EdgeDatabase:
    def __init__(self, path: Path):
        self.path = path

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def migrate(self) -> None:
        with self.connect() as db:
            version = int(db.execute("PRAGMA user_version").fetchone()[0])
            if version > SCHEMA_VERSION:
                raise RuntimeError("Banco Edge criado por uma versao mais nova.")
            if version < 1:
                db.executescript(
                    """
                    CREATE TABLE edge_state (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL,
                        updated_at TEXT NOT NULL
                    );
                    CREATE TABLE cached_entities (
                        entity_type TEXT NOT NULL,
                        entity_id TEXT NOT NULL,
                        payload TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        PRIMARY KEY (entity_type, entity_id)
                    );
                    CREATE INDEX ix_cached_entities_type
                        ON cached_entities(entity_type);
                    CREATE TABLE inbox_events (
                        stream TEXT NOT NULL,
                        cursor INTEGER NOT NULL,
                        event_key TEXT,
                        payload TEXT NOT NULL,
                        received_at TEXT NOT NULL,
                        PRIMARY KEY (stream, cursor)
                    );
                    CREATE TABLE outbox_events (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        event_key TEXT NOT NULL UNIQUE,
                        event_type TEXT NOT NULL,
                        aggregate_id TEXT,
                        payload TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'pending',
                        attempts INTEGER NOT NULL DEFAULT 0,
                        available_at TEXT NOT NULL,
                        last_error TEXT,
                        created_at TEXT NOT NULL,
                        sent_at TEXT
                    );
                    CREATE INDEX ix_edge_outbox_ready
                        ON outbox_events(status, available_at, id);
                    """
                )
                db.execute("PRAGMA user_version = 1")
                version = 1
            if version < 2:
                db.executescript(
                    """
                    CREATE TABLE local_print_jobs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        cloud_job_id INTEGER NOT NULL UNIQUE,
                        job_key TEXT NOT NULL UNIQUE,
                        document_type TEXT NOT NULL,
                        payload TEXT NOT NULL,
                        attempts INTEGER NOT NULL DEFAULT 0,
                        status TEXT NOT NULL DEFAULT 'pending',
                        claimed_by TEXT,
                        lease_until TEXT,
                        last_error TEXT,
                        created_at TEXT NOT NULL,
                        finished_at TEXT
                    );
                    CREATE INDEX ix_local_print_jobs_ready
                        ON local_print_jobs(status, id);
                    """
                )
                db.execute("PRAGMA user_version = 2")
                version = 2
            if version < 3:
                db.executescript(
                    """
                    CREATE TABLE paired_terminals (
                        terminal_id INTEGER PRIMARY KEY,
                        token_hash TEXT NOT NULL UNIQUE,
                        device_label TEXT,
                        capabilities TEXT NOT NULL,
                        station_ids TEXT NOT NULL,
                        notification_mode TEXT NOT NULL,
                        priority INTEGER NOT NULL,
                        active INTEGER NOT NULL DEFAULT 1,
                        paired_at TEXT NOT NULL,
                        last_seen_at TEXT NOT NULL
                    );
                    """
                )
                db.execute("PRAGMA user_version = 3")
                version = 3
            if version < 4:
                db.executescript(
                    """
                    CREATE TABLE local_cash_sessions (
                        local_key TEXT PRIMARY KEY,
                        terminal_id INTEGER NOT NULL,
                        cash_register_number TEXT NOT NULL,
                        operator_id INTEGER NOT NULL,
                        operator_name TEXT NOT NULL,
                        opening_amount REAL NOT NULL DEFAULT 0,
                        status TEXT NOT NULL DEFAULT 'open',
                        cloud_session_id INTEGER,
                        opened_at TEXT NOT NULL,
                        closed_at TEXT
                    );
                    CREATE UNIQUE INDEX uq_edge_open_cash_register
                        ON local_cash_sessions(terminal_id, cash_register_number)
                        WHERE status = 'open';
                    """
                )
                db.execute("PRAGMA user_version = 4")
                version = 4
            if version < 5:
                db.executescript(
                    """
                    CREATE TABLE printer_bindings (
                        logical_key TEXT PRIMARY KEY,
                        logical_name TEXT NOT NULL,
                        printer_name TEXT NOT NULL,
                        copies INTEGER NOT NULL DEFAULT 1,
                        auto_print INTEGER NOT NULL DEFAULT 1,
                        updated_at TEXT NOT NULL
                    );
                    """
                )
                db.execute("PRAGMA user_version = 5")
                version = 5
            if version < 6:
                db.executescript(
                    """
                    CREATE TABLE waiter_sessions (
                        token_hash TEXT PRIMARY KEY,
                        terminal_id INTEGER NOT NULL,
                        user_email TEXT NOT NULL,
                        user_name TEXT,
                        capabilities TEXT NOT NULL,
                        active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        last_seen_at TEXT NOT NULL
                    );
                    CREATE INDEX ix_waiter_sessions_terminal
                        ON waiter_sessions(terminal_id);
                    """
                )
                db.execute("PRAGMA user_version = 6")
                version = 6
            if version < 7:
                db.executescript(
                    """
                    ALTER TABLE waiter_sessions ADD COLUMN session_type TEXT NOT NULL DEFAULT 'waiter';
                    ALTER TABLE waiter_sessions ADD COLUMN operator_id INTEGER;
                    """
                )
                db.execute("PRAGMA user_version = 7")
                version = 7
            if version < 8:
                db.execute(
                    "ALTER TABLE local_cash_sessions ADD COLUMN operator_type TEXT NOT NULL DEFAULT 'pedeon_operator'"
                )
                db.execute("PRAGMA user_version = 8")

    def state(self, key: str, default: str = "") -> str:
        with self.connect() as db:
            row = db.execute(
                "SELECT value FROM edge_state WHERE key = ?", (key,)
            ).fetchone()
            return str(row["value"]) if row else default

    def set_state(self, key: str, value: str) -> None:
        with self.connect() as db:
            db.execute(
                """
                INSERT INTO edge_state(key, value, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value, updated_at = excluded.updated_at
                """,
                (key, value, utc_now()),
            )

    def replace_snapshot(
        self,
        products: list[dict],
        clients: list[dict],
        operators: list[dict] | None = None,
        waiters: list[dict] | None = None,
        pedeon_operators: list[dict] | None = None,
    ) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                "DELETE FROM cached_entities WHERE entity_type IN ('product','client','operator','waiter','pedeon_operator')"
            )
            for entity_type, items in (
                ("product", products),
                ("client", clients),
                ("operator", operators or []),
            ):
                db.executemany(
                    "INSERT INTO cached_entities VALUES (?, ?, ?, ?)",
                    [
                        (entity_type, str(item["id"]), json.dumps(item), now)
                        for item in items
                    ],
                )
            for entity_type, items in (
                ("waiter", waiters or []),
                ("pedeon_operator", pedeon_operators or []),
            ):
                db.executemany(
                    "INSERT INTO cached_entities VALUES (?, ?, ?, ?)",
                    [
                        (entity_type, str(item["id"]), json.dumps(item), now)
                        for item in items
                    ],
                )

    def authorize_operator(
        self,
        code: str,
        pin: str,
        *,
        require_open_cash: bool,
        require_fiscal: bool = False,
    ) -> dict:
        normalized = code.strip().upper()
        with self.connect() as db:
            rows = db.execute(
                "SELECT payload FROM cached_entities WHERE entity_type='operator'"
            ).fetchall()
        operator = next(
            (
                json.loads(row["payload"])
                for row in rows
                if json.loads(row["payload"]).get("code", "").upper() == normalized
            ),
            None,
        )
        if operator is None or not operator.get("active", False):
            raise ValueError("Código ou senha do operador inválido.")
        if not _verify_password(pin, str(operator.get("pin_hash", ""))):
            raise ValueError("Código ou senha do operador inválido.")
        if require_open_cash and not operator.get("can_open_cash", False):
            raise PermissionError("Operador sem permissão para abrir caixa.")
        if require_fiscal and operator.get("role") != "fiscal":
            raise PermissionError("Somente um fiscal pode fechar o caixa.")
        return {key: value for key, value in operator.items() if key != "pin_hash"}

    def authorize_waiter(self, code: str, pin: str) -> dict:
        normalized = code.strip().upper()
        with self.connect() as db:
            rows = db.execute(
                "SELECT payload FROM cached_entities WHERE entity_type='waiter'"
            ).fetchall()
        operator = next(
            (
                json.loads(row["payload"])
                for row in rows
                if json.loads(row["payload"]).get("code", "").upper() == normalized
            ),
            None,
        )
        if operator is None or not operator.get("active", False):
            raise ValueError("Código ou PIN do garçom inválido.")
        if not _verify_password(pin, str(operator.get("pin_hash", ""))):
            raise ValueError("Código ou PIN do garçom inválido.")
        return {key: value for key, value in operator.items() if key != "pin_hash"}

    def authorize_pedeon_operator(self, username: str, password: str) -> dict:
        normalized = username.strip().upper()
        with self.connect() as db:
            rows = db.execute(
                "SELECT payload FROM cached_entities WHERE entity_type='pedeon_operator'"
            ).fetchall()
        operator = next(
            (
                json.loads(row["payload"])
                for row in rows
                if json.loads(row["payload"]).get("code", "").upper() == normalized
            ),
            None,
        )
        if operator is None or not operator.get("active", False):
            raise ValueError("E-mail ou senha do operador inválidos.")
        if not _verify_password(password, str(operator.get("pin_hash", ""))):
            raise ValueError("E-mail ou senha do operador inválidos.")
        return {key: value for key, value in operator.items() if key != "pin_hash"}

    def open_cash_session(
        self,
        *,
        local_key: str,
        terminal_id: int,
        cash_register_number: str,
        operator: dict,
        opening_amount: float,
        operator_type: str = "pedeon_operator",
    ) -> dict:
        now = utc_now()
        with self.connect() as db:
            existing = db.execute(
                """SELECT * FROM local_cash_sessions
                   WHERE terminal_id=? AND cash_register_number=? AND status='open'""",
                (terminal_id, cash_register_number),
            ).fetchone()
            if existing is not None:
                return dict(existing)
            db.execute(
                """INSERT INTO local_cash_sessions
                   (local_key, terminal_id, cash_register_number, operator_id,
                   operator_name, opening_amount, status, opened_at, operator_type)
                   VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?)""",
                (
                    local_key,
                    terminal_id,
                    cash_register_number,
                    int(operator["id"]),
                    str(operator["name"]),
                    opening_amount,
                    now,
                    operator_type,
                ),
            )
            payload = {
                "local_key": local_key,
                "terminal_id": terminal_id,
                "cash_register_number": cash_register_number,
                "operator_id": int(operator["id"]),
                "operator_name": str(operator["name"]),
                "operator_type": operator_type,
                "opening_amount": opening_amount,
            }
            db.execute(
                """INSERT OR IGNORE INTO outbox_events
                   (event_key, event_type, aggregate_id, payload, available_at, created_at)
                   VALUES (?, 'cash.open', ?, ?, ?, ?)""",
                (f"cash-open:{local_key}", local_key, json.dumps(payload), now, now),
            )
            return dict(
                db.execute(
                    "SELECT * FROM local_cash_sessions WHERE local_key=?", (local_key,)
                ).fetchone()
            )

    def open_cash_session_for_terminal(self, terminal_id: int) -> dict | None:
        with self.connect() as db:
            row = db.execute(
                """SELECT * FROM local_cash_sessions
                   WHERE terminal_id=? AND status='open' ORDER BY opened_at DESC LIMIT 1""",
                (terminal_id,),
            ).fetchone()
            return dict(row) if row else None

    def bind_cloud_cash_session(self, local_key: str, cloud_session_id: int) -> None:
        with self.connect() as db:
            db.execute(
                "UPDATE local_cash_sessions SET cloud_session_id=? WHERE local_key=?",
                (cloud_session_id, local_key),
            )
            rows = db.execute(
                """SELECT id, payload FROM outbox_events
                   WHERE event_type IN ('order.checkout', 'cash.close')
                     AND status='pending'"""
            ).fetchall()
            for row in rows:
                payload = json.loads(row["payload"])
                if payload.get("cash_session_local_key") == local_key:
                    payload["cash_session_id"] = cloud_session_id
                    db.execute(
                        "UPDATE outbox_events SET payload=? WHERE id=?",
                        (json.dumps(payload), row["id"]),
                    )

    def close_cash_session(
        self,
        *,
        terminal_id: int,
        fiscal: dict,
        counted_cash_amount: float,
        notes: str | None,
    ) -> dict:
        now = utc_now()
        with self.connect() as db:
            row = db.execute(
                """SELECT * FROM local_cash_sessions
                   WHERE terminal_id=? AND status='open'
                   ORDER BY opened_at DESC LIMIT 1""",
                (terminal_id,),
            ).fetchone()
            if row is None:
                raise ValueError("Nenhum caixa aberto neste terminal.")
            session = dict(row)
            payload = {
                "cash_session_local_key": session["local_key"],
                "cash_session_id": session["cloud_session_id"],
                "terminal_key": None,
                "cash_register_number": session["cash_register_number"],
                "operator_name": session["operator_name"],
                "opened_at": session["opened_at"],
                "opening_amount": session["opening_amount"],
                "counted_cash_amount": counted_cash_amount,
                "authorized_by_operator_id": int(fiscal["id"]),
                "authorized_by_operator_name": str(fiscal["name"]),
                "payments": [],
                "movements": [],
                "notes": notes,
            }
            db.execute(
                """UPDATE local_cash_sessions
                   SET status='closed', closed_at=? WHERE local_key=?""",
                (now, session["local_key"]),
            )
            db.execute(
                """INSERT OR IGNORE INTO outbox_events
                   (event_key, event_type, aggregate_id, payload, available_at, created_at)
                   VALUES (?, 'cash.close', ?, ?, ?, ?)""",
                (
                    f"cash-close:{session['local_key']}",
                    session["local_key"],
                    json.dumps(payload),
                    now,
                    now,
                ),
            )
            return {
                **session,
                "status": "closed",
                "closed_at": now,
                "authorized_by_operator_name": str(fiscal["name"]),
                "queued": True,
            }

    def replace_pedeon_catalog(self, catalog: dict) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                "DELETE FROM cached_entities WHERE entity_type IN ('catalog_store','catalog_category','catalog_product')"
            )
            store = catalog.get("store")
            if store:
                db.execute(
                    "INSERT INTO cached_entities VALUES ('catalog_store', 'current', ?, ?)",
                    (json.dumps(store), now),
                )
            for entity_type, key in (
                ("catalog_category", "categories"),
                ("catalog_product", "items"),
            ):
                db.executemany(
                    "INSERT INTO cached_entities VALUES (?, ?, ?, ?)",
                    [
                        (
                            entity_type,
                            str(item.get("id") or item.get("product_id")),
                            json.dumps(item),
                            now,
                        )
                        for item in catalog.get(key, [])
                    ],
                )

    def apply_changes(self, payload: dict) -> None:
        now = utc_now()
        with self.connect() as db:
            for entity_type, key in (
                ("product", "products"),
                ("client", "clients"),
                ("operator", "operators"),
            ):
                for item in payload.get(key, []):
                    if entity_type == "operator":
                        db.execute(
                            "DELETE FROM cached_entities WHERE entity_type IN ('waiter','pedeon_operator') AND entity_id = ?",
                            (str(item["id"]),),
                        )
                    db.execute(
                        """
                        INSERT INTO cached_entities VALUES (?, ?, ?, ?)
                        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
                            payload = excluded.payload, updated_at = excluded.updated_at
                        """,
                        (entity_type, str(item["id"]), json.dumps(item), now),
                    )
                    specialized_type = {
                        "waiter": "waiter",
                        "pedeon_operator": "pedeon_operator",
                    }.get(str(item.get("role")))
                    if specialized_type:
                        db.execute(
                            "INSERT INTO cached_entities VALUES (?, ?, ?, ?)",
                            (specialized_type, str(item["id"]), json.dumps(item), now),
                        )
            for entity_type, key in (
                ("waiter", "pedeon_waiters"),
                ("pedeon_operator", "pedeon_operators"),
            ):
                for item in payload.get(key, []):
                    db.execute(
                        """
                        INSERT INTO cached_entities VALUES (?, ?, ?, ?)
                        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
                            payload = excluded.payload, updated_at = excluded.updated_at
                        """,
                        (entity_type, str(item["id"]), json.dumps(item), now),
                    )
            for entity_type, key in (
                ("product", "deleted_product_ids"),
                ("client", "deleted_client_ids"),
                ("operator", "deleted_operator_ids"),
            ):
                db.executemany(
                    "DELETE FROM cached_entities WHERE entity_type = ? AND entity_id = ?",
                    [(entity_type, str(item_id)) for item_id in payload.get(key, [])],
                )
                if entity_type == "operator":
                    db.executemany(
                        "DELETE FROM cached_entities WHERE entity_type IN ('waiter','pedeon_operator') AND entity_id = ?",
                        [(str(item_id),) for item_id in payload.get(key, [])],
                    )
            db.executemany(
                "DELETE FROM cached_entities WHERE entity_type = 'operator' AND entity_id = ?",
                [
                    (str(item_id),)
                    for item_id in payload.get("legacy_deleted_operator_ids", [])
                ],
            )

    def store_order_events(self, events: list[dict]) -> None:
        now = utc_now()
        with self.connect() as db:
            for event in events:
                db.execute(
                    """
                    INSERT OR IGNORE INTO inbox_events
                        (stream, cursor, event_key, payload, received_at)
                    VALUES ('orders', ?, ?, ?, ?)
                    """,
                    (
                        int(event["cursor"]),
                        event.get("event_key"),
                        json.dumps(event),
                        now,
                    ),
                )
                order_id = str(event["order_id"])
                db.execute(
                    """
                    INSERT INTO cached_entities VALUES ('order', ?, ?, ?)
                    ON CONFLICT(entity_type, entity_id) DO UPDATE SET
                        payload = excluded.payload, updated_at = excluded.updated_at
                    """,
                    (order_id, json.dumps(event), now),
                )

    def list_entities(self, entity_type: str, limit: int, offset: int) -> list[dict]:
        with self.connect() as db:
            rows = db.execute(
                """
                SELECT payload FROM cached_entities
                WHERE entity_type = ? ORDER BY entity_id LIMIT ? OFFSET ?
                """,
                (entity_type, limit, offset),
            ).fetchall()
            return [json.loads(row["payload"]) for row in rows]

    def store_order_details(self, orders: list[dict]) -> None:
        now = utc_now()
        with self.connect() as db:
            for order in orders:
                public_id = order.get("public_id") or order.get("id")
                if public_id is None:
                    raise ValueError("Pedido recebido sem identificador publico.")
                db.execute(
                    """
                    INSERT INTO cached_entities VALUES ('order', ?, ?, ?)
                    ON CONFLICT(entity_type, entity_id) DO UPDATE SET
                        payload = excluded.payload, updated_at = excluded.updated_at
                    """,
                    (str(public_id), json.dumps(order), now),
                )

    def enqueue(self, event_key: str, event_type: str, aggregate_id: str | None, payload: dict) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                """
                INSERT OR IGNORE INTO outbox_events
                    (event_key, event_type, aggregate_id, payload, available_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (event_key, event_type, aggregate_id, json.dumps(payload), now, now),
            )

    def enqueue_order_transition(self, event_key: str, order_id: str, status: str) -> None:
        now = utc_now()
        with self.connect() as db:
            row = db.execute(
                "SELECT payload FROM cached_entities WHERE entity_type='order' AND entity_id=?",
                (order_id,),
            ).fetchone()
            if row is None:
                raise LookupError("Pedido local nao encontrado.")
            order = json.loads(row["payload"])
            order["status"] = status
            order["local_sync_pending"] = True
            db.execute(
                "UPDATE cached_entities SET payload=?, updated_at=? WHERE entity_type='order' AND entity_id=?",
                (json.dumps(order), now, order_id),
            )
            db.execute(
                """
                INSERT OR IGNORE INTO outbox_events
                    (event_key, event_type, aggregate_id, payload, available_at, created_at)
                VALUES (?, 'order.transition', ?, ?, ?, ?)
                """,
                (event_key, order_id, json.dumps({"status": status}), now, now),
            )

    def create_local_staff_order(
        self,
        event_key: str,
        terminal_id: int,
        source_channel: str,
        table_label: str | None,
        command_label: str | None,
        customer_name: str,
        customer_notes: str | None,
        items: list[dict],
        waiter_email: str | None = None,
        waiter_name: str | None = None,
    ) -> dict:
        now = utc_now()
        local_id = f"LOCAL-{event_key[-12:]}"
        with self.connect() as db:
            catalog = {
                int(row["entity_id"]): json.loads(row["payload"])
                for row in db.execute(
                    "SELECT entity_id, payload FROM cached_entities WHERE entity_type='catalog_product'"
                ).fetchall()
            }
            total = 0.0
            rendered_items: list[dict] = []
            for requested in items:
                product = catalog.get(int(requested["product_id"]))
                if product is None or not product.get("available", False):
                    raise ValueError("Produto indisponivel no catalogo local.")
                quantity = float(requested["quantity"])
                unit_price = float(product["price"])
                modifiers_by_id = {
                    int(option["id"]): (group, option)
                    for group in product.get("modifier_groups", [])
                    for option in group.get("options", [])
                }
                rendered_modifiers = []
                modifiers_total = 0.0
                for selected in requested.get("modifiers", []):
                    match = modifiers_by_id.get(int(selected["option_id"]))
                    if match is None:
                        raise ValueError("Opcao adicional invalida no catalogo local.")
                    group, option = match
                    selected_quantity = float(selected.get("quantity", 1))
                    option_total = float(option["price_delta"]) * selected_quantity
                    modifiers_total += option_total
                    rendered_modifiers.append({
                        "group_name": group["name"],
                        "option_name": option["name"],
                        "quantity": selected_quantity,
                        "unit_price": float(option["price_delta"]),
                        "total": option_total,
                    })
                line_total = (unit_price + modifiers_total) * quantity
                total += line_total
                rendered_items.append({
                    "product_id": int(requested["product_id"]),
                    "description": product["name"],
                    "quantity": quantity,
                    "unit": product.get("unit", "UN"),
                    "unit_price": unit_price,
                    "total": line_total,
                    "customer_notes": requested.get("customer_notes"),
                    "modifiers": rendered_modifiers,
                })
            order = {
                "id": 0,
                "public_id": local_id,
                "display_number": local_id,
                "source_channel": source_channel,
                "status": "in_preparation",
                "payment_status": "pending",
                "fulfillment_type": "dine_in",
                "customer_name": customer_name,
                "customer_phone": "local",
                "total": round(total, 2),
                "subtotal": round(total, 2),
                "discount": 0,
                "delivery_fee": 0,
                "customer_notes": customer_notes,
                "source_metadata": {
                    "entrypoint": "edge_staff",
                    "table_label": table_label,
                    "command_label": command_label,
                    "terminal_id": terminal_id,
                    "waiter_email": waiter_email,
                    "waiter_name": waiter_name,
                },
                "created_at": now,
                "items": rendered_items,
                "local_sync_pending": True,
            }
            cloud_payload = {
                "terminal_id": terminal_id,
                "idempotency_key": event_key,
                "source_channel": source_channel,
                "table_label": table_label,
                "command_label": command_label,
                "customer_name": customer_name,
                "customer_notes": customer_notes,
                "items": items,
                "waiter_email": waiter_email,
                "waiter_name": waiter_name,
            }
            db.execute(
                "INSERT INTO cached_entities VALUES ('order', ?, ?, ?)",
                (local_id, json.dumps(order), now),
            )
            db.execute(
                """
                INSERT OR IGNORE INTO outbox_events
                    (event_key, event_type, aggregate_id, payload, available_at, created_at)
                VALUES (?, 'order.create', ?, ?, ?, ?)
                """,
                (event_key, local_id, json.dumps(cloud_payload), now, now),
            )
            return order

    def replace_local_order(self, local_id: str, cloud_order: dict) -> None:
        cloud_id = str(cloud_order.get("public_id") or cloud_order.get("id"))
        with self.connect() as db:
            db.execute(
                "DELETE FROM cached_entities WHERE entity_type='order' AND entity_id=?",
                (local_id,),
            )
            db.execute(
                """
                UPDATE outbox_events
                SET aggregate_id=?,
                    status=CASE WHEN status='blocked' THEN 'pending' ELSE status END,
                    last_error=CASE WHEN status='blocked' THEN NULL ELSE last_error END
                WHERE aggregate_id=?
                  AND event_type IN ('order.transition', 'order.checkout')
                  AND status IN ('pending', 'blocked')
                """,
                (cloud_id, local_id),
            )
        cloud_order["local_sync_pending"] = False
        self.store_order_details([cloud_order])

    def enqueue_order_checkout(
        self,
        event_key: str,
        order_id: str,
        terminal_id: int,
        payment_method: str,
        amount_paid: float,
        authorization_code: str | None,
        cash_session: dict,
    ) -> dict:
        now = utc_now()
        with self.connect() as db:
            row = db.execute(
                "SELECT payload FROM cached_entities WHERE entity_type='order' AND entity_id=?",
                (order_id,),
            ).fetchone()
            if row is None:
                raise LookupError("Pedido local nao encontrado.")
            order = json.loads(row["payload"])
            if order.get("status") == "completed" and order.get("checkout_event_key"):
                return order
            if order.get("status") != "ready":
                raise ValueError("Somente pedidos prontos podem ser recebidos no caixa.")
            total = round(float(order.get("total", order.get("total_amount", 0))), 2)
            paid = round(float(amount_paid), 2)
            if paid < total:
                raise ValueError("Pagamento menor que o total do pedido.")
            if payment_method != "dinheiro" and paid != total:
                raise ValueError("Pagamento em cartao ou Pix deve ser igual ao total.")
            payload = {
                "terminal_id": terminal_id,
                "idempotency_key": event_key,
                "payment_method": payment_method,
                "amount_paid": paid,
                "authorization_code": authorization_code,
                "operator_name": cash_session["operator_name"],
                "operator_id": cash_session["operator_id"],
                "operator_type": cash_session.get("operator_type", "erp_owner"),
                "cash_register_number": cash_session["cash_register_number"],
                "cash_session_local_key": cash_session["local_key"],
                "cash_session_id": cash_session.get("cloud_session_id"),
            }
            order["status"] = "completed"
            order["payment_status"] = "confirmed"
            order["local_sync_pending"] = True
            order["checkout_event_key"] = event_key
            order["payment_method"] = payment_method
            order["amount_paid"] = paid
            order["change_amount"] = round(max(0, paid - total), 2)
            db.execute(
                "UPDATE cached_entities SET payload=?, updated_at=? WHERE entity_type='order' AND entity_id=?",
                (json.dumps(order), now, order_id),
            )
            db.execute(
                """
                INSERT OR IGNORE INTO outbox_events
                    (event_key, event_type, aggregate_id, payload, available_at, created_at)
                VALUES (?, 'order.checkout', ?, ?, ?, ?)
                """,
                (event_key, order_id, json.dumps(payload), now, now),
            )
            return order

    def ready_outbox(self, limit: int = 50) -> list[dict]:
        with self.connect() as db:
            rows = db.execute(
                """
                SELECT * FROM outbox_events
                WHERE status = 'pending'
                  AND available_at <= ?
                  AND NOT (
                    event_type IN ('order.transition', 'order.checkout')
                    AND aggregate_id LIKE 'LOCAL-%'
                    AND EXISTS (
                      SELECT 1
                      FROM outbox_events AS parent
                      WHERE parent.event_type='order.create'
                        AND parent.aggregate_id=outbox_events.aggregate_id
                        AND parent.status != 'sent'
                    )
                  )
                ORDER BY id LIMIT ?
                """,
                (utc_now(), limit),
            ).fetchall()
            return [{**dict(row), "payload": json.loads(row["payload"])} for row in rows]

    def sent_outbox_cursor(self) -> int:
        with self.connect() as db:
            row = db.execute(
                "SELECT COALESCE(MAX(id), 0) AS cursor FROM outbox_events WHERE status='sent'"
            ).fetchone()
            return int(row["cursor"])

    def mark_sent(self, row_id: int) -> None:
        with self.connect() as db:
            event = db.execute(
                "SELECT event_type, aggregate_id, payload FROM outbox_events WHERE id=?",
                (row_id,),
            ).fetchone()
            db.execute(
                "UPDATE outbox_events SET status='sent', sent_at=?, last_error=NULL WHERE id=?",
                (utc_now(), row_id),
            )
            if event and event["event_type"] == "print.result":
                result = json.loads(event["payload"])["status"]
                db.execute(
                    """
                    UPDATE local_print_jobs
                    SET status=?, claimed_by=NULL, lease_until=NULL
                    WHERE cloud_job_id=?
                    """,
                    (
                        "completed" if result == "printed" else "pending",
                        int(event["aggregate_id"]),
                    ),
                )

    def mark_failed(self, row_id: int, attempts: int, error: str) -> None:
        delay_seconds = min(300, 2 ** min(attempts, 8))
        available = datetime.fromtimestamp(
            datetime.now(timezone.utc).timestamp() + delay_seconds, timezone.utc
        ).isoformat()
        with self.connect() as db:
            db.execute(
                """
                UPDATE outbox_events SET attempts=?, available_at=?, last_error=? WHERE id=?
                """,
                (attempts, available, error[:1000], row_id),
            )

    def mark_blocked(self, row_id: int, attempts: int, error: str) -> None:
        with self.connect() as db:
            db.execute(
                "UPDATE outbox_events SET status='blocked', attempts=?, last_error=? WHERE id=?",
                (attempts, error[:1000], row_id),
            )

    def outbox_issues(self, limit: int = 100) -> list[dict]:
        with self.connect() as db:
            rows = db.execute(
                """
                SELECT id, event_key, event_type, aggregate_id, attempts,
                       last_error, created_at
                FROM outbox_events WHERE status='blocked' ORDER BY id DESC LIMIT ?
                """,
                (limit,),
            ).fetchall()
            return [dict(row) for row in rows]

    def store_print_jobs(self, jobs: list[dict]) -> None:
        with self.connect() as db:
            for job in jobs:
                db.execute(
                    """
                    INSERT INTO local_print_jobs
                        (cloud_job_id, job_key, document_type, payload, attempts,
                         status, created_at)
                    VALUES (?, ?, ?, ?, ?, 'pending', ?)
                    ON CONFLICT(cloud_job_id) DO UPDATE SET
                        payload=excluded.payload, attempts=excluded.attempts,
                        status=CASE
                            WHEN local_print_jobs.status='completed' THEN 'completed'
                            ELSE 'pending'
                        END,
                        claimed_by=NULL, lease_until=NULL,
                        last_error=NULL, finished_at=NULL
                    """,
                    (
                        int(job["id"]),
                        job["job_key"],
                        job["document_type"],
                        json.dumps(job.get("payload", {})),
                        int(job.get("attempts", 0)),
                        job.get("created_at") or utc_now(),
                    ),
                )

    def claim_print_jobs(
        self, terminal_id: str, limit: int = 10, station_ids: list[int] | None = None
    ) -> list[dict]:
        now = datetime.now(timezone.utc)
        lease = datetime.fromtimestamp(now.timestamp() + 120, timezone.utc).isoformat()
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            candidates = db.execute(
                """
                SELECT * FROM local_print_jobs
                WHERE status='pending'
                   OR (status='claimed' AND lease_until < ?)
                ORDER BY id LIMIT ?
                """,
                (now.isoformat(), max(limit, 100)),
            ).fetchall()
            allowed = set(station_ids or [])
            rows = []
            for row in candidates:
                payload = json.loads(row["payload"])
                station_id = payload.get("station_id")
                if allowed and station_id is not None and int(station_id) not in allowed:
                    continue
                rows.append(row)
                if len(rows) >= limit:
                    break
            for row in rows:
                db.execute(
                    """
                    UPDATE local_print_jobs
                    SET status='claimed', claimed_by=?, lease_until=? WHERE id=?
                    """,
                    (terminal_id, lease, row["id"]),
                )
            return [
                {**dict(row), "payload": json.loads(row["payload"])} for row in rows
            ]

    def finish_local_print_job(
        self, job_id: int, terminal_id: str, result: str, error: str | None
    ) -> dict:
        with self.connect() as db:
            row = db.execute(
                """
                SELECT * FROM local_print_jobs
                WHERE id=? AND status='claimed' AND claimed_by=?
                """,
                (job_id, terminal_id),
            ).fetchone()
            if row is None:
                raise LookupError("Impressao local inexistente ou reivindicada por outro terminal.")
            if result not in {"printed", "failed"}:
                raise ValueError("Resultado de impressao invalido.")
            db.execute(
                """
                UPDATE local_print_jobs SET status='submitted', last_error=?,
                    finished_at=?, lease_until=NULL WHERE id=?
                """,
                ((error or "")[:1000] or None, utc_now(), job_id),
            )
            event_key = f"print-result:{row['cloud_job_id']}:{result}:{row['attempts']}"
            db.execute(
                """
                INSERT OR IGNORE INTO outbox_events
                    (event_key, event_type, aggregate_id, payload, available_at, created_at)
                VALUES (?, 'print.result', ?, ?, ?, ?)
                """,
                (
                    event_key,
                    str(row["cloud_job_id"]),
                    json.dumps({"status": result, "error": error}),
                    utc_now(),
                    utc_now(),
                ),
            )
            return {"id": job_id, "event_key": event_key, "status": "submitted"}

    def printer_bindings(self) -> list[dict]:
        with self.connect() as db:
            rows = db.execute(
                "SELECT * FROM printer_bindings ORDER BY logical_name"
            ).fetchall()
            return [
                {
                    **dict(row),
                    "auto_print": bool(row["auto_print"]),
                }
                for row in rows
            ]

    def claim_bound_print_jobs(self, limit: int = 10) -> list[dict]:
        """Lease only jobs whose logical destination has an automatic binding."""
        now = datetime.now(timezone.utc)
        lease = datetime.fromtimestamp(now.timestamp() + 120, timezone.utc).isoformat()
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            rows = db.execute(
                """
                SELECT jobs.*, bindings.printer_name, bindings.copies,
                       bindings.logical_name
                FROM local_print_jobs AS jobs
                JOIN printer_bindings AS bindings
                  ON bindings.logical_key =
                     'station:' || json_extract(jobs.payload, '$.station_code')
                WHERE bindings.auto_print=1
                  AND (jobs.status='pending'
                       OR (jobs.status='claimed' AND jobs.lease_until < ?))
                ORDER BY jobs.id LIMIT ?
                """,
                (now.isoformat(), limit),
            ).fetchall()
            for row in rows:
                db.execute(
                    """
                    UPDATE local_print_jobs
                    SET status='claimed', claimed_by='edge-auto', lease_until=?
                    WHERE id=?
                    """,
                    (lease, row["id"]),
                )
            return [
                {**dict(row), "payload": json.loads(row["payload"])}
                for row in rows
            ]

    def save_printer_binding(
        self,
        logical_key: str,
        logical_name: str,
        printer_name: str,
        copies: int,
        auto_print: bool,
    ) -> dict:
        with self.connect() as db:
            db.execute(
                """
                INSERT INTO printer_bindings
                    (logical_key, logical_name, printer_name, copies, auto_print, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(logical_key) DO UPDATE SET
                    logical_name=excluded.logical_name,
                    printer_name=excluded.printer_name,
                    copies=excluded.copies,
                    auto_print=excluded.auto_print,
                    updated_at=excluded.updated_at
                """,
                (
                    logical_key,
                    logical_name,
                    printer_name,
                    copies,
                    int(auto_print),
                    utc_now(),
                ),
            )
        return next(
            item
            for item in self.printer_bindings()
            if item["logical_key"] == logical_key
        )

    def save_paired_terminal(self, authorization: dict, token_hash: str) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                """
                INSERT INTO paired_terminals
                    (terminal_id, token_hash, device_label, capabilities, station_ids,
                     notification_mode, priority, active, paired_at, last_seen_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                ON CONFLICT(terminal_id) DO UPDATE SET
                    token_hash=excluded.token_hash,
                    device_label=excluded.device_label,
                    capabilities=excluded.capabilities,
                    station_ids=excluded.station_ids,
                    notification_mode=excluded.notification_mode,
                    priority=excluded.priority,
                    active=1,
                    last_seen_at=excluded.last_seen_at
                """,
                (
                    int(authorization["terminal_id"]),
                    token_hash,
                    authorization.get("device_label"),
                    json.dumps(authorization.get("capabilities", [])),
                    json.dumps(authorization.get("station_ids", [])),
                    authorization.get("notification_mode", "badge"),
                    int(authorization.get("priority", 100)),
                    now,
                    now,
                ),
            )

    def terminal_by_token_hash(self, token_hash: str) -> dict | None:
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM paired_terminals WHERE token_hash=? AND active=1",
                (token_hash,),
            ).fetchone()
            if row is None:
                return None
            db.execute(
                "UPDATE paired_terminals SET last_seen_at=? WHERE terminal_id=?",
                (utc_now(), row["terminal_id"]),
            )
            return {
                **dict(row),
                "capabilities": json.loads(row["capabilities"]),
                "station_ids": json.loads(row["station_ids"]),
            }

    def save_waiter_session(
        self, *, token_hash: str, terminal_id: int, user_email: str, user_name: str | None
    ) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                """INSERT INTO waiter_sessions
                    (token_hash, terminal_id, user_email, user_name, capabilities, active, created_at, last_seen_at)
                    VALUES (?, ?, ?, ?, ?, 1, ?, ?)""",
                (token_hash, terminal_id, user_email, user_name, json.dumps(["view", "accept"]), now, now),
            )

    def waiter_by_token_hash(self, token_hash: str) -> dict | None:
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM waiter_sessions WHERE token_hash=? AND active=1", (token_hash,)
            ).fetchone()
            if row is None:
                return None
            db.execute("UPDATE waiter_sessions SET last_seen_at=? WHERE token_hash=?", (utc_now(), token_hash))
            return {**dict(row), "capabilities": json.loads(row["capabilities"]), "session_type": row["session_type"]}

    def save_staff_session(
        self, *, token_hash: str, terminal_id: int, user_email: str,
        user_name: str, operator_id: int, capabilities: list[str]
    ) -> None:
        now = utc_now()
        with self.connect() as db:
            db.execute(
                """INSERT INTO waiter_sessions
                    (token_hash, terminal_id, user_email, user_name, capabilities,
                     active, created_at, last_seen_at, session_type, operator_id)
                    VALUES (?, ?, ?, ?, ?, 1, ?, ?, 'pedeon_operator', ?)""",
                (token_hash, terminal_id, user_email, user_name,
                 json.dumps(capabilities), now, now, operator_id),
            )

    def staff_terminal_by_token_hash(self, token_hash: str) -> dict | None:
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM waiter_sessions WHERE token_hash=? AND active=1", (token_hash,)
            ).fetchone()
            if row is None:
                return None
            terminal = db.execute(
                "SELECT * FROM paired_terminals WHERE terminal_id=? AND active=1", (row["terminal_id"],)
            ).fetchone()
            if terminal is None:
                return None
            db.execute("UPDATE waiter_sessions SET last_seen_at=? WHERE token_hash=?", (utc_now(), token_hash))
            return {
                **dict(terminal), **dict(row),
                "capabilities": json.loads(row["capabilities"]),
                "station_ids": json.loads(terminal["station_ids"]),
                "session_type": row["session_type"],
                "user_id": row["operator_id"],
            }

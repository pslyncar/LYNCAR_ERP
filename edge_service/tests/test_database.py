import tempfile
import base64
import hashlib
import unittest
from pathlib import Path

from argon2 import PasswordHasher

from lyncar_edge.database import EdgeDatabase


class EdgeDatabaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.database = EdgeDatabase(Path(self.temp.name) / "edge.db")
        self.database.migrate()

    def tearDown(self):
        self.temp.cleanup()

    def test_waiter_login_accepts_erp_argon2id_pin_hash(self):
        pin_hash = PasswordHasher().hash("12345")
        self.database.replace_snapshot([], [], [{
            "id": 5,
            "name": "Garcom",
            "code": "GARCOM5",
            "pin_hash": pin_hash,
            "role": "waiter",
            "active": True,
        }])

        waiter = self.database.authorize_waiter("garcom5", "12345")

        self.assertEqual(waiter["name"], "Garcom")

    def test_snapshot_and_incremental_changes_are_local(self):
        self.database.replace_snapshot(
            [{"id": 1, "name": "Pao"}], [{"id": 2, "name": "Cliente"}]
        )
        self.database.apply_changes(
            {
                "products": [{"id": 1, "name": "Pao novo"}],
                "clients": [],
                "deleted_product_ids": [],
                "deleted_client_ids": [2],
            }
        )

        self.assertEqual(
            self.database.list_entities("product", 20, 0)[0]["name"], "Pao novo"
        )
        self.assertEqual(self.database.list_entities("client", 20, 0), [])

    def test_pedeon_catalog_keeps_modifiers_for_local_salon(self):
        self.database.replace_pedeon_catalog({
            "store": {"slug": "loja"},
            "categories": [{"id": 3, "name": "Lanches"}],
            "items": [{
                "product_id": 8,
                "name": "X-Burger",
                "modifier_groups": [{"id": 9, "name": "Ponto", "options": []}],
            }],
        })
        item = self.database.list_entities("catalog_product", 10, 0)[0]
        self.assertEqual(item["modifier_groups"][0]["name"], "Ponto")

    def test_automatic_print_claims_only_jobs_with_matching_destination(self):
        self.database.store_print_jobs([
            {
                "id": 10,
                "job_key": "order:1:station:1:production:v1",
                "document_type": "production_ticket",
                "payload": {"station_code": "kitchen", "items": []},
            },
            {
                "id": 11,
                "job_key": "order:1:station:2:production:v1",
                "document_type": "production_ticket",
                "payload": {"station_code": "bar", "items": []},
            },
        ])
        self.database.save_printer_binding(
            "station:kitchen", "Cozinha principal", "Printer A", 1, True
        )

        claimed = self.database.claim_bound_print_jobs()

        self.assertEqual(len(claimed), 1)
        self.assertEqual(claimed[0]["payload"]["station_code"], "kitchen")
        self.assertEqual(claimed[0]["printer_name"], "Printer A")

    def test_outbox_is_idempotent_and_durable(self):
        self.database.enqueue("event-1234567890", "order.transition", "P1", {"status": "ready"})
        self.database.enqueue("event-1234567890", "order.transition", "P1", {"status": "ready"})

        ready = self.database.ready_outbox()
        self.assertEqual(len(ready), 1)
        self.database.mark_sent(ready[0]["id"])
        self.assertEqual(self.database.ready_outbox(), [])

    def test_non_retryable_outbox_failure_becomes_visible_issue(self):
        self.database.enqueue("event-blocked-123456", "order.create", "LOCAL-1", {})
        event = self.database.ready_outbox()[0]
        self.database.mark_blocked(event["id"], 1, "Produto inválido")

        self.assertEqual(self.database.ready_outbox(), [])
        issue = self.database.outbox_issues()[0]
        self.assertEqual(issue["aggregate_id"], "LOCAL-1")
        self.assertIn("inválido", issue["last_error"])

    def test_order_feed_deduplicates_cursor(self):
        event = {
            "cursor": 5,
            "event_key": "order-event-5",
            "order_id": "P5",
            "event_type": "created",
        }
        self.database.store_order_events([event, event])

        self.assertEqual(len(self.database.list_entities("order", 20, 0)), 1)

    def test_order_detail_replaces_feed_summary(self):
        self.database.store_order_events(
            [{"cursor": 1, "order_id": "PED-1", "event_type": "created"}]
        )
        self.database.store_order_details(
            [{
                "public_id": "PED-1",
                "display_number": "#101",
                "status": "accepted",
                "items": [{"name": "X-Burger", "quantity": 2}],
            }]
        )

        cached = self.database.list_entities("order", 10, 0)
        self.assertEqual(cached[0]["items"][0]["quantity"], 2)

    def test_order_transition_is_visible_offline_and_idempotent(self):
        self.database.store_order_details(
            [{"public_id": "PED-2", "status": "accepted", "items": []}]
        )
        self.database.enqueue_order_transition("transition-ped2-ready", "PED-2", "ready")
        self.database.enqueue_order_transition("transition-ped2-ready", "PED-2", "ready")

        cached = self.database.list_entities("order", 10, 0)[0]
        self.assertEqual(cached["status"], "ready")
        self.assertTrue(cached["local_sync_pending"])
        self.assertEqual(len(self.database.ready_outbox()), 1)

    def test_staff_order_is_created_offline_with_catalog_price_and_modifier(self):
        self.database.replace_pedeon_catalog({
            "store": {"slug": "loja"},
            "categories": [{"id": 3, "name": "Lanches"}],
            "items": [{
                "product_id": 8,
                "name": "X-Burger",
                "price": 20,
                "available": True,
                "unit": "UN",
                "modifier_groups": [{
                    "id": 9,
                    "name": "Adicionais",
                    "options": [{"id": 10, "name": "Bacon", "price_delta": 3}],
                }],
            }],
        })

        order = self.database.create_local_staff_order(
            event_key="edge-order-1234567890",
            terminal_id=7,
            source_channel="onsite_waiter",
            table_label="Mesa 4",
            command_label="Comanda 12",
            customer_name="Cliente",
            customer_notes=None,
            items=[{
                "product_id": 8,
                "quantity": 2,
                "modifiers": [{"option_id": 10, "quantity": 1}],
            }],
        )

        self.assertEqual(order["total"], 46)
        self.assertEqual(order["source_metadata"]["table_label"], "Mesa 4")
        self.assertTrue(order["local_sync_pending"])
        event = self.database.ready_outbox()[0]
        self.assertEqual(event["event_type"], "order.create")
        self.assertEqual(event["payload"]["terminal_id"], 7)

    def test_checkout_is_local_idempotent_and_waits_for_cloud(self):
        self.database.store_order_details([{
            "public_id": "PED-3",
            "status": "ready",
            "total": 35.5,
            "items": [],
        }])

        first = self.database.enqueue_order_checkout(
            event_key="checkout-ped3-123456",
            order_id="PED-3",
            terminal_id=7,
            payment_method="dinheiro",
            amount_paid=40,
            authorization_code=None,
            cash_session={
                "local_key": "cash-local-123456",
                "operator_id": 3,
                "operator_name": "Ana",
                "cash_register_number": "01",
                "cloud_session_id": 9,
            },
        )
        second = self.database.enqueue_order_checkout(
            event_key="checkout-ped3-123456",
            order_id="PED-3",
            terminal_id=7,
            payment_method="dinheiro",
            amount_paid=40,
            authorization_code=None,
            cash_session={
                "local_key": "cash-local-123456",
                "operator_id": 3,
                "operator_name": "Ana",
                "cash_register_number": "01",
                "cloud_session_id": 9,
            },
        )

        self.assertEqual(first["status"], "completed")
        self.assertEqual(first["change_amount"], 4.5)
        self.assertEqual(second["checkout_event_key"], "checkout-ped3-123456")
        events = self.database.ready_outbox()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event_type"], "order.checkout")

    def test_local_transitions_wait_for_create_and_follow_cloud_id(self):
        self.database.replace_pedeon_catalog({
            "categories": [],
            "items": [{
                "id": 8,
                "name": "X-Burger",
                "price": 20,
                "unit": "UN",
                "available": True,
                "modifier_groups": [],
            }],
        })
        order = self.database.create_local_staff_order(
            event_key="edge-order-dependent-123456",
            terminal_id=7,
            source_channel="onsite_waiter",
            table_label="Mesa 4",
            command_label=None,
            customer_name="Cliente",
            customer_notes=None,
            items=[{"product_id": 8, "quantity": 1, "modifiers": []}],
        )
        local_id = order["public_id"]
        self.database.enqueue_order_transition(
            "transition-dependent-ready", local_id, "ready"
        )

        ready = self.database.ready_outbox()
        self.assertEqual([event["event_type"] for event in ready], ["order.create"])

        create_event = ready[0]
        self.database.replace_local_order(
            local_id,
            {"id": 44, "public_id": "PED-000044", "status": "awaiting_acceptance"},
        )
        self.database.mark_sent(create_event["id"])

        ready = self.database.ready_outbox()
        self.assertEqual(len(ready), 1)
        self.assertEqual(ready[0]["event_type"], "order.transition")
        self.assertEqual(ready[0]["aggregate_id"], "PED-000044")

    def test_operator_opens_cash_offline_and_cloud_binding_updates_checkout(self):
        salt = b"0123456789abcdef"
        hashed = hashlib.pbkdf2_hmac("sha256", b"1234", salt, 1000, dklen=32)
        pin_hash = "pbkdf2_sha256$1000$%s$%s" % (
            base64.b64encode(salt).decode(),
            base64.b64encode(hashed).decode(),
        )
        self.database.replace_snapshot([], [], [{
            "id": 4,
            "name": "Ana",
            "code": "ANA",
            "pin_hash": pin_hash,
            "role": "operator",
            "can_open_cash": True,
            "active": True,
        }])
        operator = self.database.authorize_operator(
            "ana", "1234", require_open_cash=True
        )
        session = self.database.open_cash_session(
            local_key="cash-session-local-1234",
            terminal_id=7,
            cash_register_number="01",
            operator=operator,
            opening_amount=20,
        )
        self.assertEqual(session["operator_name"], "Ana")
        self.assertIsNone(session["cloud_session_id"])

        self.database.store_order_details([{
            "public_id": "PED-CASH",
            "status": "ready",
            "total": 10,
            "items": [],
        }])
        self.database.enqueue_order_checkout(
            event_key="checkout-cash-123456",
            order_id="PED-CASH",
            terminal_id=7,
            payment_method="pix",
            amount_paid=10,
            authorization_code=None,
            cash_session=session,
        )
        self.database.bind_cloud_cash_session("cash-session-local-1234", 88)
        checkout = next(
            item for item in self.database.ready_outbox()
            if item["event_type"] == "order.checkout"
        )
        self.assertEqual(checkout["payload"]["cash_session_id"], 88)

    def test_fiscal_closes_cash_offline_after_pending_receipts(self):
        salt = b"0123456789abcdef"
        hashed = hashlib.pbkdf2_hmac("sha256", b"4321", salt, 1000, dklen=32)
        pin_hash = "pbkdf2_sha256$1000$%s$%s" % (
            base64.b64encode(salt).decode(),
            base64.b64encode(hashed).decode(),
        )
        self.database.replace_snapshot([], [], [{
            "id": 9,
            "name": "Fiscal",
            "code": "FISCAL",
            "pin_hash": pin_hash,
            "role": "fiscal",
            "can_open_cash": True,
            "active": True,
        }])
        fiscal = self.database.authorize_operator(
            "fiscal", "4321", require_open_cash=False, require_fiscal=True
        )
        self.database.open_cash_session(
            local_key="cash-close-local-1234",
            terminal_id=7,
            cash_register_number="01",
            operator=fiscal,
            opening_amount=20,
        )
        closed = self.database.close_cash_session(
            terminal_id=7,
            fiscal=fiscal,
            counted_cash_amount=35.5,
            notes="Conferido",
        )
        self.assertEqual(closed["status"], "closed")
        self.assertIsNone(self.database.open_cash_session_for_terminal(7))
        events = self.database.ready_outbox()
        self.assertEqual([event["event_type"] for event in events], ["cash.open", "cash.close"])
        self.database.bind_cloud_cash_session("cash-close-local-1234", 91)
        close_event = next(event for event in self.database.ready_outbox() if event["event_type"] == "cash.close")
        self.assertEqual(close_event["payload"]["cash_session_id"], 91)
        self.assertEqual(close_event["payload"]["counted_cash_amount"], 35.5)

    def test_local_order_checkout_is_repointed_after_cloud_creation(self):
        self.database.replace_pedeon_catalog({
            "store": {"slug": "loja"},
            "categories": [],
            "items": [{
                "product_id": 8,
                "name": "Produto",
                "price": 10,
                "available": True,
                "modifier_groups": [],
            }],
        })
        local = self.database.create_local_staff_order(
            event_key="edge-order-checkout-1234",
            terminal_id=7,
            source_channel="pdv_counter",
            table_label=None,
            command_label=None,
            customer_name="Cliente",
            customer_notes=None,
            items=[{"product_id": 8, "quantity": 1, "modifiers": []}],
        )
        self.database.enqueue_order_transition(
            "local-ready-123456", local["public_id"], "ready"
        )
        self.database.enqueue_order_checkout(
            event_key="local-checkout-123456",
            order_id=local["public_id"],
            terminal_id=7,
            payment_method="pix",
            amount_paid=10,
            authorization_code=None,
            cash_session={
                "local_key": "cash-local-123456",
                "operator_id": 3,
                "operator_name": "Ana",
                "cash_register_number": "01",
                "cloud_session_id": 9,
            },
        )
        self.database.replace_local_order(
            local["public_id"],
            {"public_id": "CLOUD-9", "status": "in_preparation", "items": []},
        )

        checkout = next(
            event for event in self.database.ready_outbox()
            if event["event_type"] == "order.checkout"
        )
        self.assertEqual(checkout["aggregate_id"], "CLOUD-9")

    def test_only_one_local_terminal_claims_a_print_job(self):
        self.database.store_print_jobs(
            [
                {
                    "id": 9,
                    "job_key": "print-9",
                    "document_type": "kitchen",
                    "payload": {"order": "P9"},
                    "attempts": 1,
                }
            ]
        )

        first = self.database.claim_print_jobs("kds-1")
        second = self.database.claim_print_jobs("kds-2")
        self.assertEqual(len(first), 1)
        self.assertEqual(second, [])
        submitted = self.database.finish_local_print_job(
            first[0]["id"], "kds-1", "printed", None
        )
        self.assertEqual(submitted["status"], "submitted")
        event = self.database.ready_outbox()[0]
        self.assertEqual(event["event_type"], "print.result")
        self.database.mark_sent(event["id"])
        self.assertEqual(self.database.claim_print_jobs("kds-2"), [])
        self.assertEqual(self.database.sent_outbox_cursor(), event["id"])

    def test_pairing_stores_only_token_hash_and_permissions(self):
        self.database.save_paired_terminal(
            {
                "terminal_id": 7,
                "device_label": "KDS",
                "capabilities": ["view", "prepare"],
                "station_ids": [2],
                "notification_mode": "full",
                "priority": 10,
            },
            "hash-do-token",
        )

        terminal = self.database.terminal_by_token_hash("hash-do-token")
        self.assertEqual(terminal["station_ids"], [2])
        self.assertIn("prepare", terminal["capabilities"])
        self.assertIsNone(self.database.terminal_by_token_hash("token-puro"))


if __name__ == "__main__":
    unittest.main()

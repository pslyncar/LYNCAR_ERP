import unittest

from pydantic import ValidationError

from app.modules.pedeon.application.edge_schemas import (
    EDGE_CAPABILITIES,
    EDGE_PROTOCOL_VERSION,
    EdgeHeartbeatRequest,
    EdgeRegisterRequest,
)


class PedeOnEdgeContractTests(unittest.TestCase):
    def test_registration_has_versioned_identity(self):
        payload = EdgeRegisterRequest(
            terminal_key="terminal-key-123456",
            node_key="edge-node-key-1234",
        )

        self.assertEqual(payload.protocol_version, EDGE_PROTOCOL_VERSION)
        self.assertIn("durable_outbox", EDGE_CAPABILITIES)
        self.assertIn("lan_coordination", EDGE_CAPABILITIES)

    def test_heartbeat_accepts_known_monotonic_streams(self):
        payload = EdgeHeartbeatRequest(
            terminal_key="terminal-key-123456",
            cursors={"catalog": 12, "orders": 8, "outbox": 3},
        )

        self.assertEqual(payload.cursors["orders"], 8)

    def test_heartbeat_rejects_unknown_or_negative_cursor(self):
        with self.assertRaises(ValidationError):
            EdgeHeartbeatRequest(
                terminal_key="terminal-key-123456",
                cursors={"unknown": 1},
            )
        with self.assertRaises(ValidationError):
            EdgeHeartbeatRequest(
                terminal_key="terminal-key-123456",
                cursors={"catalog": -1},
            )


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path

from lyncar_edge.api import build_app
from lyncar_edge.config import EdgeSettings


class EdgeApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        settings = EdgeSettings(
            access_token="token",
            terminal_key="terminal-key-123456",
            node_key="edge-node-key-1234",
            lan_key="local-secret",
            data_dir=Path(self.temp.name),
        )
        self.app = build_app(settings, start_background_sync=False)

    def tearDown(self):
        self.temp.cleanup()

    def test_local_contract_exposes_discovery_health_and_protected_data(self):
        routes = {route.path: route for route in self.app.routes}

        self.assertIn("/.well-known/lyncar-edge", routes)
        self.assertIn("/health", routes)
        self.assertIn("/v1/catalog/products", routes)
        self.assertIn("/v1/orders/{order_id}/transition", routes)
        self.assertIn("/v1/staff/orders", routes)
        self.assertIn("/v1/login", routes)
        self.assertIn("/v1/orders/{order_id}/checkout", routes)
        self.assertIn("/v1/sync/issues", routes)
        self.assertEqual(routes["/.well-known/lyncar-edge"].dependencies, [])
        self.assertTrue(routes["/v1/catalog/products"].dependant.dependencies)


if __name__ == "__main__":
    unittest.main()

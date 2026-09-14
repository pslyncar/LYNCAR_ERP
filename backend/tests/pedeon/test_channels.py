import unittest

from app.modules.pedeon.domain.channels import OrderSource, normalize_source_channel


class PedeOnChannelTests(unittest.TestCase):
    def test_normalizes_known_and_future_adapter_channels(self):
        self.assertEqual(normalize_source_channel(OrderSource.PEDEON), "pedeon")
        self.assertEqual(normalize_source_channel("marketplace_new"), "marketplace_new")

    def test_rejects_channel_that_cannot_be_used_as_stable_identifier(self):
        with self.assertRaisesRegex(ValueError, "Canal de origem inválido"):
            normalize_source_channel("iFood / loja 1")


if __name__ == "__main__":
    unittest.main()

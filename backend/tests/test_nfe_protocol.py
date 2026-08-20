import unittest
from types import SimpleNamespace

from lxml import etree

from app.services.nfe_protocol_sp import build_nfe_protocol_envelope


class NfeProtocolEnvelopeTests(unittest.TestCase):
    def test_builds_version_4_query_with_environment_and_key(self):
        key = "35" + "2" * 42
        xml = build_nfe_protocol_envelope(
            SimpleNamespace(environment="homologacao"),
            key,
        )
        root = etree.fromstring(xml.encode("utf-8"))

        self.assertEqual(root.findtext(".//{*}tpAmb"), "2")
        self.assertEqual(root.findtext(".//{*}xServ"), "CONSULTAR")
        self.assertEqual(root.findtext(".//{*}chNFe"), key)
        self.assertEqual(root.find(".//{*}consSitNFe").attrib["versao"], "4.00")
        self.assertIsNone(root.find(".//{*}nfeConsultaNF"))


if __name__ == "__main__":
    unittest.main()

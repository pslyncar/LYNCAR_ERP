import unittest

from lxml import etree

from app.services.fiscal_xml import build_processed_nfe_xml, is_processed_nfe_xml


class FiscalXmlTests(unittest.TestCase):
    def test_combines_signed_note_and_protocol_as_nfe_proc(self):
        signed = (
            '<NFe xmlns="http://www.portalfiscal.inf.br/nfe">'
            '<infNFe Id="NFe123" version="4.00"/></NFe>'
        )
        response = (
            '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" '
            'xmlns:n="http://www.portalfiscal.inf.br/nfe"><soap:Body>'
            '<n:protNFe versao="4.00"><n:infProt><n:cStat>100</n:cStat>'
            '</n:infProt></n:protNFe></soap:Body></soap:Envelope>'
        )

        processed = build_processed_nfe_xml(signed, response)
        root = etree.fromstring(processed.encode("utf-8"))

        self.assertEqual(etree.QName(root).localname, "nfeProc")
        self.assertIsNotNone(root.find("{*}NFe"))
        self.assertIsNotNone(root.find("{*}protNFe"))
        self.assertTrue(is_processed_nfe_xml(processed))


if __name__ == "__main__":
    unittest.main()

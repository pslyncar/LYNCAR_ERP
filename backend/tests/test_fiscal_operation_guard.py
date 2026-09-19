from types import SimpleNamespace
import unittest

from app.services.fiscal_operation_guard import (
    FiscalOperationContext,
    cfop_compatibility_issues,
    document_cfop_issues,
    operation_type_from_nature,
)


class FiscalOperationGuardTests(unittest.TestCase):
    def test_sale_document_blocks_entry_cfop_before_transmission(self) -> None:
        context = FiscalOperationContext(
            operation_type="sale",
            document_model="55",
            issuer_uf="SP",
            recipient_uf="SP",
        )

        issues = cfop_compatibility_issues("1102", context)

        self.assertEqual(
            issues,
            ["CFOP 1102 e de entrada e nao pode ser usado em documento fiscal de saida."],
        )

    def test_sale_document_blocks_internal_cfop_for_interstate_recipient(self) -> None:
        context = FiscalOperationContext(
            operation_type="sale",
            document_model="55",
            issuer_uf="SP",
            recipient_uf="MG",
        )

        issues = cfop_compatibility_issues("5102", context)

        self.assertEqual(
            issues,
            ["CFOP 5102 nao corresponde a operacao interestadual (SP → MG)."],
        )

    def test_sale_document_accepts_interstate_output_cfop(self) -> None:
        context = FiscalOperationContext(
            operation_type="sale",
            document_model="55",
            issuer_uf="SP",
            recipient_uf="MG",
        )

        self.assertEqual(cfop_compatibility_issues("6102", context), [])

    def test_nature_maps_to_output_rule_family(self) -> None:
        self.assertEqual(operation_type_from_nature("Devolucao de venda"), "return")
        self.assertEqual(operation_type_from_nature("Transferencia entre lojas"), "transfer")
        self.assertEqual(operation_type_from_nature("Venda de mercadoria"), "sale")

    def test_document_uses_final_item_snapshot_instead_of_product_field(self) -> None:
        document = SimpleNamespace(operation_nature="VENDA DE MERCADORIA", model="55")
        setting = SimpleNamespace(uf="SP")
        fiscal_sale = SimpleNamespace(
            client=SimpleNamespace(state="SP", country_code="1058"),
            items=[SimpleNamespace(description="Item corrigido", cfop="1102")],
        )

        issues = document_cfop_issues(document, setting, fiscal_sale)

        self.assertEqual(len(issues), 1)
        self.assertIn("Item 1 (Item corrigido)", issues[0])
        self.assertIn("CFOP 1102 e de entrada", issues[0])


if __name__ == "__main__":
    unittest.main()

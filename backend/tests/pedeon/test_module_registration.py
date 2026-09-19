import unittest

from app.core.permissions import PERMISSIONS, ROLE_PERMISSION_CODES
from app.services.company_modules import ALL_MODULES, PLAN_DEFAULT_MODULES


class PedeOnModuleRegistrationTests(unittest.TestCase):
    def test_module_is_available_for_master_configuration(self) -> None:
        self.assertIn("pedeon", ALL_MODULES)

    def test_module_is_not_silently_enabled_on_existing_commercial_plans(self) -> None:
        for plan_code in ("start", "pro", "business"):
            with self.subTest(plan=plan_code):
                self.assertNotIn("pedeon", PLAN_DEFAULT_MODULES[plan_code])

    def test_permissions_are_separated_by_responsibility(self) -> None:
        codes = {
            permission.code
            for permission in PERMISSIONS
            if permission.module == "pedeon"
        }
        self.assertEqual(
            codes,
            {
                "pedeon:view",
                "pedeon:orders",
                "pedeon:catalog",
                "pedeon:payments",
                "pedeon:terminals",
                "pedeon:settings",
            },
        )

    def test_seller_can_operate_pedeon_when_company_module_is_enabled(self) -> None:
        self.assertIn("pedeon:view", ROLE_PERMISSION_CODES["seller"])
        self.assertIn("pedeon:orders", ROLE_PERMISSION_CODES["seller"])
        self.assertNotIn("pedeon:settings", ROLE_PERMISSION_CODES["seller"])


if __name__ == "__main__":
    unittest.main()

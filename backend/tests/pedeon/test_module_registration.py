import unittest

from app.core.permissions import PERMISSIONS
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


if __name__ == "__main__":
    unittest.main()

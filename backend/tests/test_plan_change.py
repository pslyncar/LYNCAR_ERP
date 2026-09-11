from types import SimpleNamespace
from unittest.mock import patch

from app.services.plan_change import _modules_for


def test_plan_change_preserves_manual_grants_and_revocations():
    company = SimpleNamespace(
        business_type="padaria",
        manual_module_grants=["production"],
        manual_module_revocations=["stock"],
    )

    with (
        patch(
            "app.services.company_modules.segment_default_modules",
            return_value=["dashboard", "stock"],
        ),
        patch(
            "app.services.company_modules.plan_default_modules",
            return_value=["dashboard", "stock"],
        ),
    ):
        modules = _modules_for(company, "start", "padaria")

    assert modules == ["dashboard", "production"]

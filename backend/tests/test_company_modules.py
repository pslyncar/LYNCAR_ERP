from unittest.mock import patch

from app.services.company_modules import modules_for_business_type, resolve_effective_modules


def test_inherited_modules_are_intersection_of_plan_and_segment():
    with (
        patch(
            "app.services.company_modules.segment_default_modules",
            return_value=["dashboard", "products", "service_orders"],
        ),
        patch(
            "app.services.company_modules.plan_default_modules",
            return_value=["dashboard", "products", "production"],
        ),
    ):
        assert modules_for_business_type("padaria", None, "pro") == [
            "dashboard",
            "products",
        ]


def test_manual_grants_and_revocations_are_applied_after_inheritance():
    with (
        patch(
            "app.services.company_modules.segment_default_modules",
            return_value=["dashboard", "products", "service_orders"],
        ),
        patch(
            "app.services.company_modules.plan_default_modules",
            return_value=["dashboard", "products", "production"],
        ),
    ):
        assert resolve_effective_modules(
            "padaria",
            "pro",
            manual_grants=["service_orders"],
            manual_revocations=["products"],
        ) == ["dashboard", "service_orders"]


def test_explicit_company_modules_remain_an_individual_exception():
    assert modules_for_business_type("padaria", ["production"], "start") == ["production"]

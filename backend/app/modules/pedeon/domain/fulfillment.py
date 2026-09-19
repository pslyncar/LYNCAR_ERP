"""Regras puras de roteamento operacional do PedeOn."""

from typing import Literal

ExperienceMode = Literal["food_service", "retail"]
FulfillmentMode = Literal["preparation", "picking", "none"]
InheritedFulfillmentMode = Literal["inherit", "preparation", "picking", "none"]
PrintPolicy = Literal["disabled", "manual", "automatic"]
InheritedPrintPolicy = Literal["inherit", "disabled", "manual", "automatic"]


def default_fulfillment_for_experience(experience_mode: ExperienceMode) -> FulfillmentMode:
    return "preparation" if experience_mode == "food_service" else "picking"


def resolve_fulfillment_mode(
    store_default: FulfillmentMode,
    product_override: InheritedFulfillmentMode,
) -> FulfillmentMode:
    return store_default if product_override == "inherit" else product_override


def resolve_print_policy(
    store_policy: PrintPolicy,
    product_override: InheritedPrintPolicy,
) -> PrintPolicy:
    return store_policy if product_override == "inherit" else product_override

from datetime import datetime, time
from zoneinfo import ZoneInfo

from app.modules.pedeon.infrastructure.database.models import PedeOnStore


_DAY_KEYS = (
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
)


def store_is_accepting_orders(store: PedeOnStore, now: datetime | None = None) -> bool:
    """Return the effective state; manual mode keeps the explicit store switch."""
    operation = (getattr(store, "settings", None) or {}).get(
        "delivery_operation", {}
    )
    if operation.get("opening_mode", "manual") != "schedule":
        return bool(store.accepting_orders)
    local_now = now or datetime.now(ZoneInfo(store.timezone or "America/Sao_Paulo"))
    if local_now.tzinfo is None:
        local_now = local_now.replace(tzinfo=ZoneInfo(store.timezone or "America/Sao_Paulo"))
    weekly = operation.get("weekly_hours") or {}
    current = local_now.timetz().replace(tzinfo=None)
    day = weekly.get(_DAY_KEYS[local_now.weekday()], {})
    if day.get("enabled", False):
        opens = time.fromisoformat(day.get("open_time", "08:00"))
        closes = time.fromisoformat(day.get("close_time", "18:00"))
        if opens < closes and opens <= current < closes:
            return True
        if opens > closes and current >= opens:
            return True
    # Depois da meia-noite, o expediente pertence ao dia anterior.
    previous = weekly.get(_DAY_KEYS[(local_now.weekday() - 1) % 7], {})
    if previous.get("enabled", False):
        opens = time.fromisoformat(previous.get("open_time", "08:00"))
        closes = time.fromisoformat(previous.get("close_time", "18:00"))
        if opens > closes and current < closes:
            return True
    return False

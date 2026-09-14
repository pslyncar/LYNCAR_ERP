import unittest
from datetime import datetime
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.modules.pedeon.application.operating_hours import store_is_accepting_orders


class OperatingHoursTests(unittest.TestCase):
    def test_manual_mode_uses_explicit_switch(self):
        store = SimpleNamespace(settings={}, accepting_orders=True, timezone="America/Sao_Paulo")
        self.assertTrue(store_is_accepting_orders(store))

    def test_schedule_closes_outside_interval(self):
        store = SimpleNamespace(
            accepting_orders=True,
            timezone="America/Sao_Paulo",
            settings={"delivery_operation": {"opening_mode": "schedule", "weekly_hours": {
                "monday": {"enabled": True, "open_time": "08:00", "close_time": "18:00"},
            }}},
        )
        monday = datetime(2026, 8, 24, 19, 0, tzinfo=ZoneInfo("America/Sao_Paulo"))
        self.assertFalse(store_is_accepting_orders(store, monday))

    def test_schedule_supports_overnight_interval(self):
        store = SimpleNamespace(
            accepting_orders=False,
            timezone="America/Sao_Paulo",
            settings={"delivery_operation": {"opening_mode": "schedule", "weekly_hours": {
                "monday": {"enabled": True, "open_time": "18:00", "close_time": "02:00"},
            }}},
        )
        monday = datetime(2026, 8, 24, 23, 30, tzinfo=ZoneInfo("America/Sao_Paulo"))
        self.assertTrue(store_is_accepting_orders(store, monday))


if __name__ == "__main__":
    unittest.main()

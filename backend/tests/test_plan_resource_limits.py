import unittest
from unittest.mock import Mock, patch

from fastapi import HTTPException

from app.services.plan_limits import (
    enforce_pdv_terminal_limit,
    enforce_user_limit,
    maximum_configured_limit,
)


def _session_with_count(count: int) -> Mock:
    db = Mock()
    db.get_bind.return_value.dialect.name = "sqlite"
    db.scalar.return_value = count
    return db


class PlanResourceLimitsTest(unittest.TestCase):
    def test_maximum_configured_limit_uses_highest_source(self) -> None:
        self.assertEqual(maximum_configured_limit(5, 12, 8), 12)
        self.assertIsNone(maximum_configured_limit(None, "", 0))

    @patch("app.services.plan_limits.company_plan_limits")
    def test_pdv_limit_blocks_only_new_terminal(self, mock_limits: Mock) -> None:
        mock_limits.return_value = {"max_pdv_terminals": 2}
        db = _session_with_count(2)

        enforce_pdv_terminal_limit(db, "cliente", adding_new_terminal=False)
        with self.assertRaises(HTTPException) as caught:
            enforce_pdv_terminal_limit(db, "cliente", adding_new_terminal=True)

        self.assertEqual(caught.exception.status_code, 403)
        self.assertIn("(2/2)", str(caught.exception.detail))

    @patch("app.services.plan_limits.company_plan_limits")
    def test_user_limit_blocks_activation_at_capacity(self, mock_limits: Mock) -> None:
        mock_limits.return_value = {"max_users": 5}
        db = _session_with_count(5)

        with self.assertRaises(HTTPException) as caught:
            enforce_user_limit(db, "cliente", activating_new_user=True)

        self.assertEqual(caught.exception.status_code, 403)
        self.assertIn("(5/5)", str(caught.exception.detail))


if __name__ == "__main__":
    unittest.main()

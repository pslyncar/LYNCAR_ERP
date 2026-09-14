from __future__ import annotations

import requests

from .config import EdgeSettings


class CloudClient:
    def __init__(self, settings: EdgeSettings):
        self.settings = settings
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {settings.access_token}",
                "Accept": "application/json",
            }
        )

    def set_access_token(self, access_token: str) -> None:
        self.settings.access_token = access_token
        self.session.headers["Authorization"] = f"Bearer {access_token}"

    def _url(self, path: str) -> str:
        return f"{self.settings.cloud_url.rstrip('/')}{path}"

    def _json(self, method: str, path: str, **kwargs) -> dict:
        response = self.session.request(
            method,
            self._url(path),
            timeout=self.settings.request_timeout_seconds,
            **kwargs,
        )
        try:
            response.raise_for_status()
        except requests.HTTPError as exc:
            detail = None
            try:
                payload = response.json()
                if isinstance(payload, dict):
                    detail = payload.get("detail")
            except ValueError:
                detail = None
            if detail:
                raise requests.HTTPError(
                    f"{response.status_code}: {detail}",
                    response=response,
                    request=response.request,
                ) from exc
            raise
        return response.json()

    def register(self) -> dict:
        return self._json(
            "POST",
            "/pedeon/edge/register",
            json={
                "terminal_key": self.settings.terminal_key,
                "node_key": self.settings.node_key,
                "device_label": "Lyncar Edge",
                "app_version": "0.1.0",
                "protocol_version": 1,
            },
        )

    def snapshot(self) -> dict:
        return self._json("GET", "/pdv/sync/snapshot")

    def edge_catalog(self) -> dict:
        return self._json(
            "GET",
            "/pedeon/edge/catalog/operational",
            params={"terminal_key": self.settings.terminal_key},
        )

    def edge_catalog_revision(self) -> int:
        payload = self._json(
            "GET",
            "/pedeon/edge/catalog/revision",
            params={"terminal_key": self.settings.terminal_key},
        )
        return int(payload.get("revision", 0))

    def changes(self, after: int, limit: int = 500) -> dict:
        return self._json(
            "GET", "/pdv/sync/changes", params={"after": after, "limit": limit}
        )

    def order_feed(self, after: int, limit: int = 100) -> dict:
        return self._json(
            "GET",
            "/pedeon/terminals/feed",
            params={
                "terminal_key": self.settings.terminal_key,
                "after": after,
                "limit": limit,
            },
        )

    def order_detail(self, public_id: str) -> dict:
        return self._json(
            "GET",
            f"/pedeon/terminals/orders/{public_id}",
            params={"terminal_key": self.settings.terminal_key},
        )

    def heartbeat(self, cursors: dict[str, int], last_error: str | None) -> dict:
        return self._json(
            "POST",
            f"/pedeon/edge/{self.settings.node_key}/heartbeat",
            json={
                "terminal_key": self.settings.terminal_key,
                "cursors": cursors,
                "last_error": last_error,
            },
        )

    def transition_order(self, order_id: str, status: str) -> dict:
        return self._json(
            "PATCH",
            f"/pedeon/terminals/orders/{order_id}/status",
            params={"terminal_key": self.settings.terminal_key},
            json={"status": status},
        )

    def create_staff_order(self, payload: dict) -> dict:
        body = {
            **payload,
            "edge_node_key": self.settings.node_key,
            "edge_terminal_key": self.settings.terminal_key,
        }
        return self._json("POST", "/pedeon/edge/orders", json=body)

    def checkout_order(self, order_id: str, payload: dict) -> dict:
        body = {
            **payload,
            "edge_node_key": self.settings.node_key,
            "edge_terminal_key": self.settings.terminal_key,
        }
        return self._json(
            "POST", f"/pedeon/edge/orders/{order_id}/checkout", json=body
        )

    def open_cash_session(self, payload: dict) -> dict:
        body = {
            **payload,
            "edge_node_key": self.settings.node_key,
            "edge_terminal_key": self.settings.terminal_key,
        }
        return self._json("POST", "/pedeon/edge/cash-sessions/open", json=body)

    def close_cash_session(self, payload: dict) -> dict:
        return self._json("POST", "/pdv/closings", json=payload)

    def claim_print_jobs(self, limit: int = 25) -> list[dict]:
        result = self.session.get(
            self._url("/pedeon/terminals/print-jobs"),
            params={"terminal_key": self.settings.terminal_key, "limit": limit},
            timeout=self.settings.request_timeout_seconds,
        )
        result.raise_for_status()
        return result.json()

    def finish_print_job(self, job_id: int, status: str, error: str | None) -> dict:
        return self._json(
            "PATCH",
            f"/pedeon/terminals/print-jobs/{job_id}",
            params={"terminal_key": self.settings.terminal_key},
            json={"status": status, "error": error},
        )

    def authorize_terminal(self, terminal_key: str) -> dict:
        return self._json(
            "POST",
            "/pedeon/edge/authorize-terminal",
            json={
                "edge_node_key": self.settings.node_key,
                "edge_terminal_key": self.settings.terminal_key,
                "terminal_key": terminal_key,
            },
        )

    def login_pedeon(self, email: str, password: str) -> tuple[dict, list[dict]]:
        """Authenticate an administrator and return PedeOn-enabled PDV slots.

        The cloud credentials are used only for this activation request.  The
        returned long-lived local session is still issued by the Edge.
        """
        response = requests.post(
            self._url("/auth/login/automatic"),
            json={
                "email": email,
                "password": password,
                "client_type": "pedeon_pos",
            },
            headers={"Accept": "application/json"},
            timeout=self.settings.request_timeout_seconds,
        )
        response.raise_for_status()
        login = response.json()
        headers = {
            "Authorization": f"Bearer {login['access_token']}",
            "Accept": "application/json",
        }
        settings_response = requests.get(
            self._url("/pedeon/settings"),
            headers=headers,
            timeout=self.settings.request_timeout_seconds,
        )
        settings_response.raise_for_status()
        terminals_response = requests.get(
            self._url("/pedeon/terminals"),
            headers=headers,
            timeout=self.settings.request_timeout_seconds,
        )
        terminals_response.raise_for_status()
        settings = settings_response.json()
        terminals = terminals_response.json()
        # Keep the identity returned by the same authenticated session. The
        # PedeOn cash session must be owned by the logged-in ERP owner, not by
        # a legacy operator code/PIN.
        try:
            identity = requests.get(
                self._url("/auth/me"),
                headers={"Authorization": f"Bearer {login['access_token']}", "Accept": "application/json"},
                timeout=self.settings.request_timeout_seconds,
            )
            identity.raise_for_status()
            login["user"] = identity.json()
        except requests.RequestException:
            login["user"] = {"email": email}
        allowed_ids = {
            int(item["terminal_id"])
            for item in settings.get("terminals", [])
            if item.get("enabled") and item.get("terminal_active")
        }
        available = [
            item
            for item in terminals
            if int(item.get("id", 0)) in allowed_ids
            and item.get("active")
            and item.get("activation_status") == "active"
            and not str(item.get("terminal_key", "")).startswith("pending:")
        ]
        return login, available

    def login_waiter(self, email: str, password: str) -> dict:
        response = requests.post(
            self._url("/auth/login/automatic"),
            json={
                "email": email,
                "password": password,
                "client_type": "pedeon_salon",
            },
            headers={"Accept": "application/json"},
            timeout=self.settings.request_timeout_seconds,
        )
        response.raise_for_status()
        return response.json()

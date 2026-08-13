from urllib.parse import urlencode

import requests

from app.services.master_integrations import get_mercado_livre_app_config

PROVIDER = "mercado_livre"
AUTH_URL = "https://auth.mercadolivre.com.br/authorization"
TOKEN_URL = "https://api.mercadolibre.com/oauth/token"
ME_URL = "https://api.mercadolibre.com/users/me"
API_BASE_URL = "https://api.mercadolibre.com"


def mercado_livre_credentials_configured() -> bool:
    return get_mercado_livre_app_config().configured


def build_authorization_url(state: str) -> str:
    config = get_mercado_livre_app_config()
    if not config.client_id or not config.redirect_uri:
        return ""
    query = urlencode(
        {
            "response_type": "code",
            "client_id": config.client_id,
            "redirect_uri": config.redirect_uri,
            "state": state,
        }
    )
    return f"{AUTH_URL}?{query}"


def exchange_authorization_code(code: str) -> dict:
    config = get_mercado_livre_app_config()
    response = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "client_id": config.client_id,
            "client_secret": config.client_secret,
            "code": code,
            "redirect_uri": config.redirect_uri,
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def fetch_current_user(access_token: str) -> dict:
    response = requests.get(
        ME_URL,
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def refresh_access_token(refresh_token: str) -> dict:
    config = get_mercado_livre_app_config()
    response = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "refresh_token",
            "client_id": config.client_id,
            "client_secret": config.client_secret,
            "refresh_token": refresh_token,
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def fetch_user_item_ids(
    access_token: str,
    seller_id: str,
    *,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    response = requests.get(
        f"{API_BASE_URL}/users/{seller_id}/items/search",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"limit": limit, "offset": offset},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def fetch_items(access_token: str, item_ids: list[str]) -> list[dict]:
    if not item_ids:
        return []
    response = requests.get(
        f"{API_BASE_URL}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"ids": ",".join(item_ids)},
        timeout=30,
    )
    response.raise_for_status()
    rows = response.json()
    if not isinstance(rows, list):
        return []
    return [
        row.get("body") or {}
        for row in rows
        if isinstance(row, dict) and int(row.get("code") or 0) < 400
    ]

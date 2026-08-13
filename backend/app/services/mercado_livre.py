from urllib.parse import urlencode

import requests

from app.core.config import get_settings

PROVIDER = "mercado_livre"
AUTH_URL = "https://auth.mercadolivre.com.br/authorization"
TOKEN_URL = "https://api.mercadolibre.com/oauth/token"
ME_URL = "https://api.mercadolibre.com/users/me"


def mercado_livre_credentials_configured() -> bool:
    settings = get_settings()
    return bool(
        settings.mercado_livre_client_id
        and settings.mercado_livre_client_secret
        and settings.mercado_livre_redirect_uri
    )


def build_authorization_url(state: str) -> str:
    settings = get_settings()
    if not settings.mercado_livre_client_id or not settings.mercado_livre_redirect_uri:
        return ""
    query = urlencode(
        {
            "response_type": "code",
            "client_id": settings.mercado_livre_client_id,
            "redirect_uri": settings.mercado_livre_redirect_uri,
            "state": state,
        }
    )
    return f"{AUTH_URL}?{query}"


def exchange_authorization_code(code: str) -> dict:
    settings = get_settings()
    response = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "client_id": settings.mercado_livre_client_id,
            "client_secret": settings.mercado_livre_client_secret,
            "code": code,
            "redirect_uri": settings.mercado_livre_redirect_uri,
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

import base64
import hashlib
from dataclasses import dataclass

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.models.master_integration_setting import MasterIntegrationSetting

MERCADO_LIVRE_PROVIDER = "mercado_livre"


@dataclass(frozen=True)
class MercadoLivreAppConfig:
    client_id: str | None
    client_secret: str | None
    redirect_uri: str | None
    webhook_url: str | None
    source: str

    @property
    def configured(self) -> bool:
        return bool(self.client_id and self.client_secret and self.redirect_uri)

    @property
    def client_secret_configured(self) -> bool:
        return bool(self.client_secret)


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


def _fernet() -> Fernet:
    digest = hashlib.sha256(get_settings().secret_key.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def _encrypt_secret(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("utf-8")


def _decrypt_secret(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return _fernet().decrypt(value.encode("utf-8")).decode("utf-8")
    except InvalidToken:
        return None


def get_mercado_livre_app_config(db: Session | None = None) -> MercadoLivreAppConfig:
    close_db = db is None
    session = db or MasterSessionLocal()
    try:
        settings = get_settings()
        row = session.get(MasterIntegrationSetting, MERCADO_LIVRE_PROVIDER)
        row_has_values = bool(
            row
            and (
                row.client_id
                or row.client_secret_encrypted
                or row.redirect_uri
                or row.webhook_url
            )
        )
        return MercadoLivreAppConfig(
            client_id=_clean(row.client_id if row else None)
            or _clean(settings.mercado_livre_client_id),
            client_secret=_decrypt_secret(row.client_secret_encrypted if row else None)
            or _clean(settings.mercado_livre_client_secret),
            redirect_uri=_clean(row.redirect_uri if row else None)
            or _clean(settings.mercado_livre_redirect_uri),
            webhook_url=_clean(row.webhook_url if row else None)
            or _clean(settings.mercado_livre_webhook_url),
            source="database" if row_has_values else "environment",
        )
    finally:
        if close_db:
            session.close()


def upsert_mercado_livre_app_config(
    db: Session,
    *,
    client_id: str,
    client_secret: str | None,
    redirect_uri: str,
    webhook_url: str | None,
) -> MercadoLivreAppConfig:
    row = db.get(MasterIntegrationSetting, MERCADO_LIVRE_PROVIDER)
    if row is None:
        row = MasterIntegrationSetting(provider=MERCADO_LIVRE_PROVIDER)
        db.add(row)
    row.client_id = _clean(client_id)
    row.redirect_uri = _clean(redirect_uri)
    row.webhook_url = _clean(webhook_url)
    if _clean(client_secret):
        row.client_secret_encrypted = _encrypt_secret(client_secret.strip())
    db.commit()
    db.refresh(row)
    return get_mercado_livre_app_config(db)

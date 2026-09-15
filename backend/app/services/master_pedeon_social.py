import base64
import hashlib
import json
from dataclasses import dataclass

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.master_pedeon_social_setting import MasterPedeonSocialSetting

PROVIDERS = ("google", "facebook", "apple")
PUBLIC_SOCIAL_CALLBACK_BASE = "https://api.lyncar.com.br/pedeon/public/auth"


def default_redirect_uri(provider: str) -> str:
    """Return the single platform callback used by a social provider.

    Customer storefront subdomains are carried in OAuth ``state`` and are
    never registered as provider callbacks. This keeps one credential usable
    by every LynCar tenant.
    """
    if provider not in PROVIDERS:
        raise ValueError(f"Provedor social inválido: {provider}")
    return f"{PUBLIC_SOCIAL_CALLBACK_BASE}/{provider}/callback"


@dataclass(frozen=True)
class PedeOnSocialConfig:
    provider: str
    client_id: str | None
    client_secret: str | None
    redirect_uri: str | None
    extra: dict[str, str | None]
    enabled: bool

    @property
    def configured(self) -> bool:
        if self.provider == "apple":
            return bool(self.client_id and self.extra.get("team_id") and self.extra.get("key_id") and self.extra.get("private_key"))
        return bool(self.client_id and self.client_secret and self.redirect_uri)


def _fernet() -> Fernet:
    digest = hashlib.sha256(get_settings().secret_key.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def _encrypt(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("utf-8")


def _decrypt(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return _fernet().decrypt(value.encode("utf-8")).decode("utf-8")
    except InvalidToken:
        return None


def _clean(value: str | None) -> str | None:
    value = value.strip() if value else None
    return value or None


def get_configs(db: Session) -> list[PedeOnSocialConfig]:
    rows = {row.provider: row for row in db.query(MasterPedeonSocialSetting).all()}
    result = []
    for provider in PROVIDERS:
        row = rows.get(provider)
        raw_extra = _decrypt(row.extra_encrypted if row else None)
        try:
            extra = json.loads(raw_extra) if raw_extra else {}
        except (TypeError, ValueError):
            extra = {}
        result.append(PedeOnSocialConfig(
            provider=provider,
            client_id=_clean(row.client_id if row else None),
            client_secret=_decrypt(row.client_secret_encrypted if row else None),
            redirect_uri=_clean(row.redirect_uri if row else None) or default_redirect_uri(provider),
            extra={str(k): _clean(str(v)) if v is not None else None for k, v in extra.items()},
            enabled=bool(row.enabled) if row else False,
        ))
    return result


def upsert_config(db: Session, payload) -> PedeOnSocialConfig:
    row = db.get(MasterPedeonSocialSetting, payload.provider)
    if row is None:
        row = MasterPedeonSocialSetting(provider=payload.provider)
        db.add(row)
    row.client_id = _clean(payload.client_id)
    row.redirect_uri = _clean(payload.redirect_uri)
    row.enabled = payload.enabled
    if _clean(payload.client_secret):
        row.client_secret_encrypted = _encrypt(payload.client_secret.strip())
    extra = {key: _clean(value) for key, value in payload.extra.items() if value is not None and _clean(value)}
    if extra:
        row.extra_encrypted = _encrypt(json.dumps(extra, ensure_ascii=False))
    db.commit()
    db.refresh(row)
    return next(config for config in get_configs(db) if config.provider == payload.provider)

import base64
import hashlib
from dataclasses import dataclass

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.models.master_email_setting import MasterEmailSetting

EMAIL_PROVIDER = "password_recovery"


@dataclass(frozen=True)
class MasterEmailConfig:
    provider: str
    auth_method: str
    smtp_host: str | None
    smtp_port: int
    username: str | None
    client_id: str | None
    from_email: str | None
    from_name: str | None
    enabled: bool
    password_configured: bool
    client_secret_configured: bool
    refresh_token_configured: bool

    @property
    def configured(self) -> bool:
        if not self.enabled or not self.from_email:
            return False
        if self.auth_method == "gmail_api":
            return bool(self.client_id and self.client_secret_configured and self.refresh_token_configured)
        return bool(self.smtp_host and self.smtp_port and self.username and self.password_configured)


def _fernet() -> Fernet:
    digest = hashlib.sha256(get_settings().secret_key.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def _encrypt(value: str | None) -> str | None:
    if not value or not value.strip():
        return None
    return _fernet().encrypt(value.strip().encode("utf-8")).decode("utf-8")


def _configured(value: str | None) -> bool:
    if not value:
        return False
    try:
        _fernet().decrypt(value.encode("utf-8"))
        return True
    except InvalidToken:
        return False


def get_master_email_config(db: Session | None = None) -> MasterEmailConfig:
    close_db = db is None
    session = db or MasterSessionLocal()
    try:
        row = session.get(MasterEmailSetting, EMAIL_PROVIDER)
        return MasterEmailConfig(
            provider=EMAIL_PROVIDER,
            auth_method=row.auth_method if row else "smtp",
            smtp_host=row.smtp_host if row else None,
            smtp_port=row.smtp_port if row else 587,
            username=row.username if row else None,
            client_id=row.client_id if row else None,
            from_email=row.from_email if row else None,
            from_name=row.from_name if row else None,
            enabled=row.enabled if row else False,
            password_configured=_configured(row.password_encrypted if row else None),
            client_secret_configured=_configured(row.client_secret_encrypted if row else None),
            refresh_token_configured=_configured(row.refresh_token_encrypted if row else None),
        )
    finally:
        if close_db:
            session.close()


def upsert_master_email_config(db: Session, payload) -> MasterEmailConfig:
    row = db.get(MasterEmailSetting, EMAIL_PROVIDER)
    if row is None:
        row = MasterEmailSetting(provider=EMAIL_PROVIDER)
        db.add(row)
    row.auth_method = payload.auth_method
    row.smtp_host = payload.smtp_host.strip() if payload.smtp_host else None
    row.smtp_port = payload.smtp_port
    row.username = payload.username.strip() if payload.username else None
    row.client_id = payload.client_id.strip() if payload.client_id else None
    row.from_email = str(payload.from_email) if payload.from_email else None
    row.from_name = payload.from_name.strip() if payload.from_name else None
    row.enabled = payload.enabled
    for field, column in (
        (payload.password, "password_encrypted"),
        (payload.client_secret, "client_secret_encrypted"),
        (payload.refresh_token, "refresh_token_encrypted"),
    ):
        encrypted = _encrypt(field)
        if encrypted:
            setattr(row, column, encrypted)
    db.commit()
    db.refresh(row)
    return get_master_email_config(db)

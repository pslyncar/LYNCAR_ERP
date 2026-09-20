import base64
import hashlib
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage

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
        if not self.enabled:
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


def _decrypt(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return _fernet().decrypt(value.encode("utf-8")).decode("utf-8")
    except InvalidToken:
        return None


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


def send_password_reset_email(
    *, recipient: str, code: str, company_name: str | None = None
) -> None:
    """Send a reset code using the encrypted master SMTP configuration."""
    with MasterSessionLocal() as db:
        row = db.get(MasterEmailSetting, EMAIL_PROVIDER)
        if row is None:
            raise RuntimeError("E-mail de recuperação não configurado.")
        config = get_master_email_config(db)
        if not config.configured:
            raise RuntimeError("E-mail de recuperação não está habilitado.")
        password = _decrypt(row.password_encrypted)
        if not password:
            raise RuntimeError("Senha SMTP inválida ou ausente.")

    sender = (config.from_email or config.username or "").strip()
    message = EmailMessage()
    message["Subject"] = "Código para redefinir sua senha — Lyncar"
    message["From"] = f"{config.from_name} <{sender}>" if config.from_name else sender
    message["To"] = recipient
    greeting = f"Olá{', ' + company_name if company_name else ''}!"
    message.set_content(
        f"{greeting}\n\n"
        f"Seu código para redefinir a senha do Lyncar é: {code}\n\n"
        "Ele expira em 15 minutos e só pode ser usado uma vez.\n"
        "Se você não solicitou essa alteração, ignore este e-mail.\n\nLyncar"
    )
    if config.smtp_port == 465:
        with smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=20) as smtp:
            smtp.login(config.username, password)
            smtp.send_message(message)
    else:
        with smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(config.username, password)
            smtp.send_message(message)

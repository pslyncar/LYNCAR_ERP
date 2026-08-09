from fastapi import APIRouter, Depends
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.models.payment_setting import PaymentSetting
from app.schemas.payment_setting import PaymentSettingRead, PaymentSettingUpdate

router = APIRouter()


def _preview(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) <= 12:
        return "***"
    return f"{value[:8]}...{value[-6:]}"


def _read(setting: PaymentSetting | None) -> PaymentSettingRead:
    settings = get_settings()
    public_key = setting.public_key if setting else settings.mercado_pago_public_key
    access_token = setting.access_token if setting else settings.mercado_pago_access_token
    webhook_url = setting.webhook_url if setting else settings.mercado_pago_webhook_url
    environment = setting.environment if setting else "test"
    active = setting.active if setting else True
    return PaymentSettingRead(
        provider="mercado_pago",
        environment=environment,
        public_key=public_key,
        access_token_configured=bool(access_token),
        access_token_preview=_preview(access_token),
        webhook_url=webhook_url,
        active=active,
    )


@router.get("/payment-settings/mercado-pago", response_model=PaymentSettingRead)
def get_mercado_pago_setting(_: dict = Depends(require_master_permission("master:billing"))) -> PaymentSettingRead:
    with MasterSessionLocal() as db:
        setting = db.scalar(
            select(PaymentSetting).where(PaymentSetting.provider == "mercado_pago")
        )
        return _read(setting)


@router.put("/payment-settings/mercado-pago", response_model=PaymentSettingRead)
def update_mercado_pago_setting(
    payload: PaymentSettingUpdate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> PaymentSettingRead:
    with MasterSessionLocal() as db:
        setting = db.scalar(
            select(PaymentSetting).where(PaymentSetting.provider == "mercado_pago")
        )
        if setting is None:
            setting = PaymentSetting(provider="mercado_pago")
            db.add(setting)
        setting.environment = payload.environment
        setting.public_key = payload.public_key.strip() if payload.public_key else None
        if payload.access_token and payload.access_token.strip():
            setting.access_token = payload.access_token.strip()
        setting.webhook_url = payload.webhook_url.strip() if payload.webhook_url else None
        setting.active = payload.active
        db.commit()
        db.refresh(setting)
        return _read(setting)

from fastapi import APIRouter, Depends

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.schemas.master_email import MasterEmailSettingRead, MasterEmailSettingUpdate
from app.services.master_email import get_master_email_config, upsert_master_email_config

router = APIRouter()


def _serialize(config):
    return MasterEmailSettingRead(
        provider=config.provider,
        auth_method=config.auth_method,
        smtp_host=config.smtp_host,
        smtp_port=config.smtp_port,
        username=config.username,
        client_id=config.client_id,
        from_email=config.from_email,
        from_name=config.from_name,
        enabled=config.enabled,
        password_configured=config.password_configured,
        client_secret_configured=config.client_secret_configured,
        refresh_token_configured=config.refresh_token_configured,
        configured=config.configured,
    )


@router.get("/email-settings", response_model=MasterEmailSettingRead)
def get_email_settings(_user=Depends(require_master_permission("master:integrations"))):
    with MasterSessionLocal() as db:
        return _serialize(get_master_email_config(db))


@router.put("/email-settings", response_model=MasterEmailSettingRead)
def update_email_settings(
    payload: MasterEmailSettingUpdate,
    _user=Depends(require_master_permission("master:integrations")),
):
    with MasterSessionLocal() as db:
        return _serialize(upsert_master_email_config(db, payload))

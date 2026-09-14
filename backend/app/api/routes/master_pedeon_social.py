from fastapi import APIRouter, Depends

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.schemas.master_pedeon_social import PedeOnSocialProviderRead, PedeOnSocialProviderUpdate
from app.services.master_pedeon_social import get_configs, upsert_config

router = APIRouter()


def _read(config):
    extra_configured = bool(config.extra) and all(config.extra.get(key) for key in ("team_id", "key_id", "private_key"))
    return PedeOnSocialProviderRead(
        provider=config.provider,
        client_id=config.client_id,
        redirect_uri=config.redirect_uri,
        enabled=config.enabled,
        configured=config.configured,
        client_secret_configured=bool(config.client_secret),
        extra_configured=extra_configured,
    )


@router.get("/integrations/pedeon-social", response_model=list[PedeOnSocialProviderRead])
def read_pedeon_social(_user=Depends(require_master_permission("master:integrations"))):
    with MasterSessionLocal() as db:
        return [_read(config) for config in get_configs(db)]


@router.put("/integrations/pedeon-social", response_model=list[PedeOnSocialProviderRead])
def update_pedeon_social(payload: PedeOnSocialProviderUpdate, _user=Depends(require_master_permission("master:integrations"))):
    with MasterSessionLocal() as db:
        upsert_config(db, payload)
        return [_read(config) for config in get_configs(db)]

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.schemas.marketplace import (
    MercadoLivreAppConfigRead,
    MercadoLivreAppConfigUpdate,
)
from app.services.master_integrations import (
    MercadoLivreAppConfig,
    get_mercado_livre_app_config,
    upsert_mercado_livre_app_config,
)

router = APIRouter()


def _serialize(config: MercadoLivreAppConfig) -> MercadoLivreAppConfigRead:
    return MercadoLivreAppConfigRead(
        client_id=config.client_id,
        redirect_uri=config.redirect_uri,
        webhook_url=config.webhook_url,
        configured=config.configured,
        client_secret_configured=config.client_secret_configured,
        source=config.source,
    )


@router.get("/integrations/mercado-livre", response_model=MercadoLivreAppConfigRead)
def read_mercado_livre_config(
    _user=Depends(require_master_permission("master:integrations")),
):
    with MasterSessionLocal() as db:
        return _serialize(get_mercado_livre_app_config(db))


@router.put("/integrations/mercado-livre", response_model=MercadoLivreAppConfigRead)
def update_mercado_livre_config(
    payload: MercadoLivreAppConfigUpdate,
    _user=Depends(require_master_permission("master:integrations")),
):
    with MasterSessionLocal() as db:
        current = get_mercado_livre_app_config(db)
        if not payload.client_secret and not current.client_secret_configured:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Informe o Client Secret do Mercado Livre.",
            )
        config = upsert_mercado_livre_app_config(
            db,
            client_id=payload.client_id,
            client_secret=payload.client_secret,
            redirect_uri=payload.redirect_uri,
            webhook_url=payload.webhook_url,
        )
        return _serialize(config)

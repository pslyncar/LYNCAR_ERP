from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe

from fastapi import APIRouter, Depends, HTTPException, status
import requests
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import require_permission
from app.core.database import get_db
from app.models.marketplace import (
    MarketplaceConnection,
    MarketplaceNotification,
    MarketplaceOAuthState,
    ProductMarketplaceListing,
)
from app.models.product import Product
from app.models.user import User
from app.schemas.marketplace import (
    MarketplaceProductRead,
    MercadoLivreAuthUrlRead,
    MercadoLivreStatusRead,
    ProductMarketplaceListingRead,
    ProductMarketplaceListingUpdate,
)
from app.services.mercado_livre import (
    PROVIDER,
    build_authorization_url,
    exchange_authorization_code,
    fetch_current_user,
    mercado_livre_credentials_configured,
)
from app.services.tenancy import session_for_company

router = APIRouter()


def _parse_ml_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def _serialize_listing(
    product: Product,
    listing: ProductMarketplaceListing | None,
) -> ProductMarketplaceListingRead:
    if listing is None:
        return ProductMarketplaceListingRead(
            id=None,
            product_id=product.id,
            provider=PROVIDER,
            listing_id=None,
            enabled=False,
            sync_stock=True,
            sync_price=True,
            status="not_configured",
            title=product.name,
            category_id=None,
            listing_type_id=None,
            condition="new",
            permalink=None,
            last_error=None,
            last_synced_at=None,
            created_at=None,
            updated_at=None,
        )
    return ProductMarketplaceListingRead.model_validate(listing)


def _current_connection(db: Session) -> MarketplaceConnection | None:
    return db.scalar(
        select(MarketplaceConnection)
        .where(MarketplaceConnection.provider == PROVIDER)
        .order_by(MarketplaceConnection.updated_at.desc(), MarketplaceConnection.id.desc())
    )


@router.get("/mercado-livre/status", response_model=MercadoLivreStatusRead)
def mercado_livre_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:view")),
) -> MercadoLivreStatusRead:
    configured = mercado_livre_credentials_configured()
    connection = _current_connection(db)
    if connection is None:
        return MercadoLivreStatusRead(
            configured=configured,
            connected=False,
            message=(
                "Credenciais do app Mercado Livre configuradas. Clique em conectar."
                if configured
                else "Configure CLIENT_ID, CLIENT_SECRET e REDIRECT_URI do Mercado Livre no servidor."
            ),
        )
    return MercadoLivreStatusRead(
        configured=configured,
        connected=bool(connection.access_token and connection.status == "connected"),
        message="Conta Mercado Livre conectada."
        if connection.status == "connected"
        else "Conexao pendente.",
        account_id=connection.account_id,
        nickname=connection.nickname,
        site_id=connection.site_id,
        expires_at=connection.expires_at,
        last_sync_at=connection.last_sync_at,
    )


@router.get("/mercado-livre/auth-url", response_model=MercadoLivreAuthUrlRead)
def mercado_livre_auth_url(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:connect")),
) -> MercadoLivreAuthUrlRead:
    if not mercado_livre_credentials_configured():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Credenciais do Mercado Livre nao configuradas no servidor.",
        )
    state = f"{current_user.company_code}.{token_urlsafe(32)}"
    db.add(
        MarketplaceOAuthState(
            provider=PROVIDER,
            state=state,
            tenant_code=current_user.company_code,
            created_by_user_id=current_user.id,
            expires_at=datetime.now(UTC) + timedelta(minutes=15),
        )
    )
    db.commit()
    return MercadoLivreAuthUrlRead(auth_url=build_authorization_url(state), state=state)


@router.get("/mercado-livre/callback")
def mercado_livre_callback(
    code: str,
    state: str,
) -> dict[str, str]:
    if not mercado_livre_credentials_configured():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Credenciais do Mercado Livre nao configuradas no servidor.",
        )
    if "." not in state:
        raise HTTPException(status_code=400, detail="Estado OAuth invalido.")
    tenant_code = state.split(".", 1)[0]
    with session_for_company(tenant_code) as state_db:
        oauth_state = state_db.scalar(
            select(MarketplaceOAuthState).where(
                MarketplaceOAuthState.provider == PROVIDER,
                MarketplaceOAuthState.state == state,
            )
        )
        if oauth_state is None:
            raise HTTPException(status_code=400, detail="Estado OAuth invalido.")
        if oauth_state.used_at is not None:
            raise HTTPException(status_code=400, detail="Estado OAuth ja utilizado.")
        if oauth_state.expires_at < datetime.now(UTC):
            raise HTTPException(status_code=400, detail="Estado OAuth expirado.")
        tenant_code = oauth_state.tenant_code

    try:
        token_data = exchange_authorization_code(code)
        access_token = token_data.get("access_token")
        if not access_token:
            raise HTTPException(
                status_code=400,
                detail="Mercado Livre nao retornou access_token.",
            )
        account = fetch_current_user(access_token)
    except requests.HTTPError as exc:
        detail = exc.response.text if exc.response is not None else str(exc)
        raise HTTPException(status_code=400, detail=detail) from exc
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=400,
            detail="Falha ao comunicar com Mercado Livre.",
        ) from exc

    with session_for_company(tenant_code) as tenant_db:
        account_id = str(account.get("id") or token_data.get("user_id") or "")
        connection = tenant_db.scalar(
            select(MarketplaceConnection).where(
                MarketplaceConnection.provider == PROVIDER,
                MarketplaceConnection.account_id == account_id,
            )
        )
        if connection is None:
            connection = MarketplaceConnection(provider=PROVIDER, account_id=account_id)
            tenant_db.add(connection)
        expires_in = token_data.get("expires_in")
        connection.nickname = account.get("nickname")
        connection.site_id = account.get("site_id")
        connection.status = "connected"
        connection.access_token = access_token
        connection.refresh_token = token_data.get("refresh_token")
        connection.token_type = token_data.get("token_type")
        connection.scopes = token_data.get("scope", "").split()
        connection.raw_account = account
        connection.expires_at = (
            datetime.now(UTC) + timedelta(seconds=int(expires_in))
            if expires_in
            else None
        )
        connection.last_sync_at = datetime.now(UTC)
        tenant_db.commit()

        oauth_state.used_at = datetime.now(UTC)
        state_db.commit()
    return {
        "status": "connected",
        "message": "Mercado Livre conectado. Volte ao Lyncar e atualize a tela.",
    }


@router.post("/mercado-livre/notifications")
def mercado_livre_notifications(
    payload: dict,
    db: Session = Depends(get_db),
) -> dict[str, str]:
    user_id = payload.get("user_id")
    application_id = payload.get("application_id")
    notification = MarketplaceNotification(
        provider=PROVIDER,
        topic=payload.get("topic"),
        resource=payload.get("resource"),
        external_user_id=str(user_id) if user_id is not None else None,
        application_id=str(application_id) if application_id is not None else None,
        attempts=payload.get("attempts"),
        sent_at=_parse_ml_datetime(payload.get("sent")),
        payload=payload,
    )
    db.add(notification)
    db.commit()
    return {"status": "received"}


@router.get("/mercado-livre/products", response_model=list[MarketplaceProductRead])
def list_mercado_livre_products(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:products")),
) -> list[MarketplaceProductRead]:
    products = db.scalars(select(Product).order_by(Product.name)).all()
    product_ids = [product.id for product in products]
    listings: dict[int, ProductMarketplaceListing] = {}
    if product_ids:
        rows = db.scalars(
            select(ProductMarketplaceListing).where(
                ProductMarketplaceListing.provider == PROVIDER,
                ProductMarketplaceListing.product_id.in_(product_ids),
            )
        ).all()
        listings = {row.product_id: row for row in rows}
    return [
        MarketplaceProductRead(
            product_id=product.id,
            name=product.name,
            internal_code=product.internal_code,
            barcode=product.barcode,
            sale_price=product.sale_price,
            stock_quantity=product.stock_quantity,
            active=product.active,
            listing=_serialize_listing(product, listings.get(product.id)),
        )
        for product in products
    ]


@router.put(
    "/mercado-livre/products/{product_id}",
    response_model=ProductMarketplaceListingRead,
)
def update_mercado_livre_product(
    product_id: int,
    payload: ProductMarketplaceListingUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:products")),
) -> ProductMarketplaceListingRead:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto nao encontrado.")
    listing = db.scalar(
        select(ProductMarketplaceListing).where(
            ProductMarketplaceListing.product_id == product_id,
            ProductMarketplaceListing.provider == PROVIDER,
        )
    )
    if listing is None:
        listing = ProductMarketplaceListing(product_id=product_id, provider=PROVIDER)
        db.add(listing)
    for field, value in payload.model_dump().items():
        setattr(listing, field, value)
    listing.status = "ready" if listing.enabled else "paused"
    listing.last_error = None
    db.commit()
    db.refresh(listing)
    return ProductMarketplaceListingRead.model_validate(listing)

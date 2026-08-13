from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe

from fastapi import APIRouter, Depends, HTTPException, status
import requests
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.dependencies import require_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.marketplace import (
    MarketplaceConnection,
    MarketplaceNotification,
    MarketplaceOAuthState,
    MarketplaceSyncJob,
    ProductMarketplaceListing,
)
from app.models.product import Product
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.marketplace import (
    MarketplaceProductRead,
    MercadoLivreImportPreviewRead,
    MercadoLivreListingImportItem,
    MercadoLivreListingLink,
    MercadoLivreAuthUrlRead,
    MercadoLivreStatusRead,
    ProductMarketplaceListingRead,
    ProductMarketplaceListingUpdate,
)
from app.services.mercado_livre import (
    PROVIDER,
    build_authorization_url,
    exchange_authorization_code,
    fetch_items,
    fetch_current_user,
    fetch_user_item_ids,
    mercado_livre_credentials_configured,
    refresh_access_token,
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


def _enabled_listing_count(db: Session, exclude_product_id: int | None = None) -> int:
    statement = select(func.count(ProductMarketplaceListing.id)).where(
        ProductMarketplaceListing.provider == PROVIDER,
        ProductMarketplaceListing.enabled.is_(True),
    )
    if exclude_product_id is not None:
        statement = statement.where(ProductMarketplaceListing.product_id != exclude_product_id)
    return int(db.scalar(statement) or 0)


def _marketplace_listing_limit(company_code: str) -> int | None:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return None
        override = (company.plan_overrides or {}).get("marketplace_listing_limit")
        if override is not None:
            try:
                return int(override)
            except (TypeError, ValueError):
                return None
        plan = master_db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == company.plan))
        return plan.marketplace_listing_limit if plan is not None else None


def _enforce_listing_limit(
    db: Session,
    company_code: str,
    *,
    product_id: int,
    enabled: bool,
) -> None:
    if not enabled:
        return
    limit = _marketplace_listing_limit(company_code)
    if limit is None:
        return
    current = _enabled_listing_count(db, exclude_product_id=product_id)
    if current >= limit:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Limite de {limit} anuncio(s) do Mercado Livre atingido para este plano.",
        )


def _queue_sync_job(
    db: Session,
    *,
    job_type: str,
    product_id: int | None = None,
    listing_id: str | None = None,
    resource: str | None = None,
    payload: dict | None = None,
) -> MarketplaceSyncJob:
    job = MarketplaceSyncJob(
        provider=PROVIDER,
        job_type=job_type,
        product_id=product_id,
        listing_id=listing_id,
        resource=resource,
        payload=payload or {},
    )
    db.add(job)
    return job


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _ensure_valid_connection(db: Session) -> MarketplaceConnection:
    connection = _current_connection(db)
    if connection is None or connection.status != "connected" or not connection.access_token:
        raise HTTPException(status_code=400, detail="Mercado Livre nao conectado.")
    expires_at = _as_utc(connection.expires_at)
    if (
        connection.refresh_token
        and expires_at is not None
        and expires_at <= datetime.now(UTC) + timedelta(minutes=5)
    ):
        try:
            token_data = refresh_access_token(connection.refresh_token)
        except requests.RequestException as exc:
            raise HTTPException(
                status_code=400,
                detail="Falha ao renovar token do Mercado Livre.",
            ) from exc
        access_token = token_data.get("access_token")
        if not access_token:
            raise HTTPException(status_code=400, detail="Mercado Livre nao retornou access_token.")
        expires_in = token_data.get("expires_in")
        connection.access_token = access_token
        connection.refresh_token = token_data.get("refresh_token") or connection.refresh_token
        connection.token_type = token_data.get("token_type") or connection.token_type
        connection.scopes = token_data.get("scope", "").split() or connection.scopes
        connection.expires_at = (
            datetime.now(UTC) + timedelta(seconds=int(expires_in))
            if expires_in
            else connection.expires_at
        )
        connection.last_sync_at = datetime.now(UTC)
        db.commit()
        db.refresh(connection)
    return connection


def _normalize_key(value: str | None) -> str:
    return "".join(ch for ch in (value or "").lower() if ch.isalnum())


@router.get("/mercado-livre/status", response_model=MercadoLivreStatusRead)
def mercado_livre_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:view")),
) -> MercadoLivreStatusRead:
    configured = mercado_livre_credentials_configured()
    connection = _current_connection(db)
    listing_limit = _marketplace_listing_limit(current_user.company_code)
    enabled_listings = _enabled_listing_count(db)
    pending_jobs = int(
        db.scalar(
            select(func.count(MarketplaceSyncJob.id)).where(
                MarketplaceSyncJob.provider == PROVIDER,
                MarketplaceSyncJob.status == "pending",
            )
        )
        or 0
    )
    if connection is None:
        return MercadoLivreStatusRead(
            configured=configured,
            connected=False,
            listing_limit=listing_limit,
            enabled_listings=enabled_listings,
            remaining_listings=(
                None if listing_limit is None else max(listing_limit - enabled_listings, 0)
            ),
            pending_jobs=pending_jobs,
            message=(
                "Credenciais do app Mercado Livre configuradas. Clique em conectar."
                if configured
                else "Integração Mercado Livre em implantação. Fale com o suporte para liberar a conexão."
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
        listing_limit=listing_limit,
        enabled_listings=enabled_listings,
        remaining_listings=(
            None if listing_limit is None else max(listing_limit - enabled_listings, 0)
        ),
        pending_jobs=pending_jobs,
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
        oauth_state_expires_at = _as_utc(oauth_state.expires_at)
        if oauth_state_expires_at is None or oauth_state_expires_at < datetime.now(UTC):
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
        oauth_state = tenant_db.scalar(
            select(MarketplaceOAuthState).where(
                MarketplaceOAuthState.provider == PROVIDER,
                MarketplaceOAuthState.state == state,
            )
        )
        if oauth_state is None or oauth_state.used_at is not None:
            raise HTTPException(status_code=400, detail="Estado OAuth invalido.")
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
        oauth_state.used_at = datetime.now(UTC)
        tenant_db.commit()
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
    db.flush()
    _queue_sync_job(
        db,
        job_type="process_notification",
        resource=notification.resource,
        payload={"notification_id": notification.id, "payload": payload},
    )
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
    _enforce_listing_limit(
        db,
        current_user.company_code,
        product_id=product_id,
        enabled=payload.enabled,
    )
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
    if listing.enabled:
        _queue_sync_job(
            db,
            job_type="sync_product_listing",
            product_id=product_id,
            listing_id=listing.listing_id,
            payload=payload.model_dump(),
        )
    db.commit()
    db.refresh(listing)
    return ProductMarketplaceListingRead.model_validate(listing)


@router.get(
    "/mercado-livre/listings/import-preview",
    response_model=MercadoLivreImportPreviewRead,
)
def preview_mercado_livre_listings(
    limit: int = 30,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:products")),
) -> MercadoLivreImportPreviewRead:
    del current_user
    connection = _ensure_valid_connection(db)
    if not connection.account_id:
        raise HTTPException(status_code=400, detail="Conta Mercado Livre sem seller id.")
    limit = min(max(limit, 1), 50)
    offset = max(offset, 0)
    try:
        search_data = fetch_user_item_ids(
            connection.access_token or "",
            connection.account_id,
            limit=limit,
            offset=offset,
        )
        item_ids = [str(item) for item in search_data.get("results") or [] if item]
        items = fetch_items(connection.access_token or "", item_ids)
    except requests.HTTPError as exc:
        detail = exc.response.text if exc.response is not None else str(exc)
        raise HTTPException(status_code=400, detail=detail) from exc
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=400,
            detail="Falha ao consultar anuncios do Mercado Livre.",
        ) from exc

    products = db.scalars(select(Product)).all()
    products_by_key: dict[str, Product] = {}
    for product in products:
        for key in (
            _normalize_key(product.internal_code),
            _normalize_key(product.barcode),
        ):
            if key:
                products_by_key.setdefault(key, product)

    listing_ids = [str(item.get("id")) for item in items if item.get("id")]
    existing_by_listing_id: dict[str, ProductMarketplaceListing] = {}
    if listing_ids:
        existing = db.scalars(
            select(ProductMarketplaceListing).where(
                ProductMarketplaceListing.provider == PROVIDER,
                ProductMarketplaceListing.listing_id.in_(listing_ids),
            )
        ).all()
        existing_by_listing_id = {row.listing_id or "": row for row in existing}

    preview_items: list[MercadoLivreListingImportItem] = []
    for item in items:
        listing_id = str(item.get("id") or "")
        seller_custom_field = item.get("seller_custom_field")
        matched_product = products_by_key.get(_normalize_key(seller_custom_field))
        existing_listing = existing_by_listing_id.get(listing_id)
        if existing_listing is not None:
            matched_product = db.get(Product, existing_listing.product_id) or matched_product
        preview_items.append(
            MercadoLivreListingImportItem(
                listing_id=listing_id,
                title=str(item.get("title") or ""),
                status=item.get("status"),
                price=item.get("price"),
                available_quantity=item.get("available_quantity"),
                permalink=item.get("permalink"),
                thumbnail=item.get("thumbnail"),
                category_id=item.get("category_id"),
                listing_type_id=item.get("listing_type_id"),
                condition=item.get("condition"),
                seller_custom_field=(
                    str(seller_custom_field) if seller_custom_field is not None else None
                ),
                local_product_id=matched_product.id if matched_product is not None else None,
                local_product_name=matched_product.name if matched_product is not None else None,
                already_linked=existing_listing is not None,
            )
        )
    return MercadoLivreImportPreviewRead(
        total=int(search_data.get("paging", {}).get("total") or len(preview_items)),
        offset=offset,
        limit=limit,
        results=preview_items,
    )


@router.post(
    "/mercado-livre/listings/link",
    response_model=ProductMarketplaceListingRead,
)
def link_mercado_livre_listing(
    payload: MercadoLivreListingLink,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("marketplaces:products")),
) -> ProductMarketplaceListingRead:
    product = db.get(Product, payload.product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produto nao encontrado.")
    _enforce_listing_limit(
        db,
        current_user.company_code,
        product_id=payload.product_id,
        enabled=payload.enabled,
    )
    existing_for_listing = db.scalar(
        select(ProductMarketplaceListing).where(
            ProductMarketplaceListing.provider == PROVIDER,
            ProductMarketplaceListing.listing_id == payload.listing_id,
            ProductMarketplaceListing.product_id != payload.product_id,
        )
    )
    if existing_for_listing is not None:
        raise HTTPException(
            status_code=400,
            detail="Este anuncio ja esta vinculado a outro produto.",
        )
    listing = db.scalar(
        select(ProductMarketplaceListing).where(
            ProductMarketplaceListing.product_id == payload.product_id,
            ProductMarketplaceListing.provider == PROVIDER,
        )
    )
    if listing is None:
        listing = ProductMarketplaceListing(
            product_id=payload.product_id,
            provider=PROVIDER,
        )
        db.add(listing)
    listing.listing_id = payload.listing_id
    listing.title = listing.title or product.name
    listing.enabled = payload.enabled
    listing.sync_stock = payload.sync_stock
    listing.sync_price = payload.sync_price
    listing.status = "linked" if payload.enabled else "paused"
    listing.last_error = None
    _queue_sync_job(
        db,
        job_type="sync_product_listing",
        product_id=product.id,
        listing_id=payload.listing_id,
        payload=payload.model_dump(),
    )
    db.commit()
    db.refresh(listing)
    return ProductMarketplaceListingRead.model_validate(listing)

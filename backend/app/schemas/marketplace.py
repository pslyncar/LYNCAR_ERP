from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class MercadoLivreStatusRead(BaseModel):
    configured: bool
    connected: bool
    message: str
    account_id: str | None = None
    nickname: str | None = None
    site_id: str | None = None
    expires_at: datetime | None = None
    last_sync_at: datetime | None = None
    listing_limit: int | None = None
    enabled_listings: int = 0
    remaining_listings: int | None = None
    pending_jobs: int = 0


class MercadoLivreAuthUrlRead(BaseModel):
    auth_url: str
    state: str


class MercadoLivreAppConfigRead(BaseModel):
    client_id: str | None = None
    redirect_uri: str | None = None
    webhook_url: str | None = None
    configured: bool
    client_secret_configured: bool
    source: str


class MercadoLivreAppConfigUpdate(BaseModel):
    client_id: str = Field(min_length=1, max_length=120)
    client_secret: str | None = Field(default=None, max_length=255)
    redirect_uri: str = Field(min_length=1, max_length=500)
    webhook_url: str | None = Field(default=None, max_length=500)


class ProductMarketplaceListingUpdate(BaseModel):
    enabled: bool
    sync_stock: bool = True
    sync_price: bool = True
    title: str | None = Field(default=None, max_length=180)
    category_id: str | None = Field(default=None, max_length=60)
    listing_type_id: str | None = Field(default=None, max_length=60)
    condition: str = Field(default="new", max_length=20)


class ProductMarketplaceListingRead(ProductMarketplaceListingUpdate):
    id: int | None = None
    product_id: int
    provider: str
    listing_id: str | None = None
    status: str
    permalink: str | None = None
    last_error: str | None = None
    last_synced_at: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class MarketplaceProductRead(BaseModel):
    product_id: int
    name: str
    internal_code: str | None = None
    barcode: str | None = None
    sale_price: Decimal
    stock_quantity: Decimal
    active: bool
    listing: ProductMarketplaceListingRead


class MercadoLivreListingImportItem(BaseModel):
    listing_id: str
    title: str
    status: str | None = None
    price: Decimal | None = None
    available_quantity: Decimal | None = None
    permalink: str | None = None
    thumbnail: str | None = None
    category_id: str | None = None
    listing_type_id: str | None = None
    condition: str | None = None
    seller_custom_field: str | None = None
    local_product_id: int | None = None
    local_product_name: str | None = None
    already_linked: bool = False


class MercadoLivreImportPreviewRead(BaseModel):
    total: int
    offset: int
    limit: int
    results: list[MercadoLivreListingImportItem]


class MercadoLivreListingLink(BaseModel):
    product_id: int
    listing_id: str = Field(min_length=3, max_length=80)
    enabled: bool = True
    sync_stock: bool = True
    sync_price: bool = True

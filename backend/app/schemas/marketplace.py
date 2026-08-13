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


class MercadoLivreAuthUrlRead(BaseModel):
    auth_url: str
    state: str


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

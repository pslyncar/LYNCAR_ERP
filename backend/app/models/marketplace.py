from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class MarketplaceConnection(Base):
    __tablename__ = "marketplace_connections"
    __table_args__ = (
        UniqueConstraint("provider", "account_id", name="uq_marketplace_connection_account"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider: Mapped[str] = mapped_column(String(40), nullable=False, default="mercado_livre")
    account_id: Mapped[Optional[str]] = mapped_column(String(80))
    nickname: Mapped[Optional[str]] = mapped_column(String(160))
    site_id: Mapped[Optional[str]] = mapped_column(String(10))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending")
    access_token: Mapped[Optional[str]] = mapped_column(Text)
    refresh_token: Mapped[Optional[str]] = mapped_column(Text)
    token_type: Mapped[Optional[str]] = mapped_column(String(40))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    scopes: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    raw_account: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    last_sync_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class ProductMarketplaceListing(Base):
    __tablename__ = "product_marketplace_listings"
    __table_args__ = (
        UniqueConstraint("product_id", "provider", name="uq_product_marketplace_provider"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(40), nullable=False, default="mercado_livre")
    listing_id: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    sync_stock: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    sync_price: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="draft")
    title: Mapped[Optional[str]] = mapped_column(String(180))
    permalink: Mapped[Optional[str]] = mapped_column(Text)
    category_id: Mapped[Optional[str]] = mapped_column(String(60))
    listing_type_id: Mapped[Optional[str]] = mapped_column(String(60))
    condition: Mapped[str] = mapped_column(String(20), nullable=False, default="new")
    last_error: Mapped[Optional[str]] = mapped_column(Text)
    last_synced_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    product = relationship("Product", back_populates="marketplace_listings")


class MarketplaceOAuthState(Base):
    __tablename__ = "marketplace_oauth_states"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider: Mapped[str] = mapped_column(String(40), nullable=False, default="mercado_livre")
    state: Mapped[str] = mapped_column(String(120), nullable=False, unique=True, index=True)
    tenant_code: Mapped[str] = mapped_column(String(120), nullable=False)
    created_by_user_id: Mapped[Optional[int]] = mapped_column(nullable=True)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class MarketplaceNotification(Base):
    __tablename__ = "marketplace_notifications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider: Mapped[str] = mapped_column(String(40), nullable=False, default="mercado_livre")
    topic: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    resource: Mapped[Optional[str]] = mapped_column(Text)
    external_user_id: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    application_id: Mapped[Optional[str]] = mapped_column(String(80))
    attempts: Mapped[Optional[int]] = mapped_column(Integer)
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="received")
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class MarketplaceSyncJob(Base):
    __tablename__ = "marketplace_sync_jobs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider: Mapped[str] = mapped_column(String(40), nullable=False, default="mercado_livre")
    job_type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending", index=True)
    product_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("products.id", ondelete="SET NULL"),
        index=True,
    )
    listing_id: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    resource: Mapped[Optional[str]] = mapped_column(Text)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[Optional[str]] = mapped_column(Text)
    scheduled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

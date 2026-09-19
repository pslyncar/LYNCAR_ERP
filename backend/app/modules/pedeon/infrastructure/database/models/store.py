from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PedeOnStore(Base):
    __tablename__ = "pedeon_stores"

    id: Mapped[int] = mapped_column(primary_key=True)
    public_slug: Mapped[str] = mapped_column(String(80), nullable=False, unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(180), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    logo_url: Mapped[str | None] = mapped_column(Text)
    cover_url: Mapped[str | None] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    accepting_orders: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    acceptance_mode: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")
    experience_mode: Mapped[str] = mapped_column(
        String(20), nullable=False, default="food_service"
    )
    business_segment: Mapped[str] = mapped_column(
        String(40), nullable=False, default="other"
    )
    default_fulfillment_mode: Mapped[str] = mapped_column(
        String(20), nullable=False, default="preparation"
    )
    production_print_policy: Mapped[str] = mapped_column(
        String(20), nullable=False, default="manual"
    )
    timezone: Mapped[str] = mapped_column(String(60), nullable=False, default="America/Sao_Paulo")
    fulfillment_options: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    minimum_order_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    settings: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnCategory(Base):
    __tablename__ = "pedeon_categories"
    __table_args__ = (
        UniqueConstraint("store_id", "slug", name="uq_pedeon_category_store_slug"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    channel: Mapped[str] = mapped_column(String(20), nullable=False, default="shared")
    slug: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    image_url: Mapped[str | None] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class PedeOnProductPublication(Base):
    __tablename__ = "pedeon_product_publications"
    __table_args__ = (
        UniqueConstraint("store_id", "product_id", name="uq_pedeon_publication_product"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[int | None] = mapped_column(
        ForeignKey("pedeon_categories.id", ondelete="SET NULL"), index=True
    )
    display_name: Mapped[str | None] = mapped_column(String(220))
    description: Mapped[str | None] = mapped_column(Text)
    image_url: Mapped[str | None] = mapped_column(Text)
    online_price: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    published: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    available: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    use_product_offer: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    fulfillment_mode: Mapped[str] = mapped_column(
        String(20), nullable=False, default="inherit"
    )
    print_policy: Mapped[str] = mapped_column(
        String(20), nullable=False, default="inherit"
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    availability_rules: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PedeOnModifierGroup(Base):
    __tablename__ = "pedeon_modifier_groups"
    __table_args__ = (
        UniqueConstraint("store_id", "code", name="uq_pedeon_modifier_group_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(80), nullable=False)
    channel: Mapped[str] = mapped_column(String(20), nullable=False, default="shared")
    kind: Mapped[str] = mapped_column(String(20), nullable=False, default="complement")
    name: Mapped[str] = mapped_column(String(140), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    minimum_selections: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    maximum_selections: Mapped[int | None] = mapped_column(Integer)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class PedeOnModifierOption(Base):
    __tablename__ = "pedeon_modifier_options"
    __table_args__ = (
        UniqueConstraint("group_id", "code", name="uq_pedeon_modifier_option_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    group_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_modifier_groups.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int | None] = mapped_column(
        ForeignKey("products.id", ondelete="SET NULL"), index=True
    )
    code: Mapped[str] = mapped_column(String(80), nullable=False)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    price_delta: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=0)
    minimum_quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    maximum_quantity: Mapped[int | None] = mapped_column(Integer)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class PedeOnProductModifierGroup(Base):
    __tablename__ = "pedeon_product_modifier_groups"
    __table_args__ = (
        UniqueConstraint(
            "publication_id", "group_id", name="uq_pedeon_publication_modifier_group"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    publication_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_product_publications.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    group_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_modifier_groups.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

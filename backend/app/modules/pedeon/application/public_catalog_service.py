from datetime import datetime, timezone
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from math import ceil
import hashlib

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.pedeon_public_store import PedeOnPublicStore
from app.models.product import Product
from app.modules.pedeon.application.public_schemas import (
    CartQuoteLineRead,
    CartQuoteRead,
    CartQuoteRequest,
    CartModifierSelection,
    EdgeCatalogProductRead,
    EdgeCatalogRead,
    PublicCatalogPageRead,
    PublicCategoryRead,
    PublicPaymentMethodRead,
    PublicModifierGroupRead,
    PublicModifierOptionRead,
    PublicProductRead,
    PublicStoreRead,
)
from app.modules.pedeon.application.delivery_service import PedeOnDeliveryService
from app.modules.pedeon.application.operating_hours import store_is_accepting_orders
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnCategory,
    PedeOnPaymentConfiguration,
    PedeOnModifierGroup,
    PedeOnModifierOption,
    PedeOnOutboxEvent,
    PedeOnProductModifierGroup,
    PedeOnProductPublication,
    PedeOnStore,
)
from app.services.tenancy import get_enabled_modules_for_company, session_for_company


MONEY = Decimal("0.01")


@dataclass(frozen=True)
class ResolvedModifier:
    group: PedeOnModifierGroup
    option: PedeOnModifierOption
    quantity: Decimal
    unit_price: Decimal

    @property
    def total(self) -> Decimal:
        return (self.unit_price * self.quantity).quantize(
            MONEY, rounding=ROUND_HALF_UP
        )


@dataclass(frozen=True)
class ResolvedCartLine:
    request: object
    publication: PedeOnProductPublication | None
    product: Product
    base_unit_price: Decimal
    modifiers: tuple[ResolvedModifier, ...]

    @property
    def modifiers_unit_amount(self) -> Decimal:
        return sum((item.total for item in self.modifiers), Decimal("0")).quantize(
            MONEY, rounding=ROUND_HALF_UP
        )

    @property
    def unit_price(self) -> Decimal:
        return (self.base_unit_price + self.modifiers_unit_amount).quantize(MONEY)

    @property
    def total(self) -> Decimal:
        return (self.unit_price * self.request.quantity).quantize(
            MONEY, rounding=ROUND_HALF_UP
        )


def effective_product_price(
    product: Product,
    publication: PedeOnProductPublication | None,
    *,
    now: datetime | None = None,
) -> tuple[Decimal, bool]:
    """Resolve o preço público sem copiar preço para outra fonte de verdade."""
    if publication is not None and publication.online_price is not None:
        return Decimal(publication.online_price).quantize(MONEY), False
    current = now or datetime.now(timezone.utc)
    offer_is_current = (
        (publication is None or publication.use_product_offer)
        and product.offer_price is not None
        and (product.offer_start_at is None or product.offer_start_at <= current)
        and (product.offer_end_at is None or product.offer_end_at >= current)
    )
    price = product.offer_price if offer_is_current else product.sale_price
    return Decimal(price).quantize(MONEY), offer_is_current


class PedeOnPublicCatalogService:
    ONLINE_CHANNEL = "pedeon_online"
    LOCAL_CHANNELS = frozenset({"onsite_waiter", "pdv_counter"})

    @staticmethod
    def _canonical_channel(channel: object) -> str:
        # `onsite_qr` was the original label used by the first Salon screen.
        # Keep old publications working while exposing the canonical Edge channel.
        return "onsite_waiter" if str(channel) == "onsite_qr" else str(channel)

    @staticmethod
    def _enabled_channels(publication: PedeOnProductPublication) -> set[str]:
        rules = publication.availability_rules or {}
        configured = rules.get("enabled_channels", ["pedeon_online"])
        return {PedeOnPublicCatalogService._canonical_channel(channel) for channel in configured}

    @classmethod
    def _enabled_for(
        cls, publication: PedeOnProductPublication, channels: set[str] | frozenset[str]
    ) -> bool:
        return bool(cls._enabled_channels(publication).intersection(channels))

    @classmethod
    def _published_for(cls, publication: PedeOnProductPublication, channel: str) -> bool:
        rules = publication.availability_rules or {}
        configured = rules.get("published_channels")
        canonical = cls._canonical_channel(channel)
        return (
            publication.published
            if configured is None
            else canonical in {cls._canonical_channel(item) for item in configured}
        )

    @classmethod
    def _available_for(cls, publication: PedeOnProductPublication, channel: str) -> bool:
        rules = publication.availability_rules or {}
        configured = rules.get("available_channels")
        canonical = cls._canonical_channel(channel)
        return (
            publication.available
            if configured is None
            else canonical in {cls._canonical_channel(item) for item in configured}
        )

    @classmethod
    def catalog(
        cls,
        slug: str,
        *,
        search: str = "",
        category: str | None = None,
        product_id: int | None = None,
        page: int = 1,
        page_size: int = 24,
    ) -> PublicCatalogPageRead:
        registry = cls._registry(slug)
        with session_for_company(registry.company_code) as db:
            store = cls._active_store(db, registry.tenant_store_id, slug)
            categories = cls._categories(db, store.id, channel="online")
            query = (
                select(PedeOnProductPublication, Product)
                .join(Product, Product.id == PedeOnProductPublication.product_id)
                .where(
                    PedeOnProductPublication.store_id == store.id,
                    Product.active.is_(True),
                )
            )
            cleaned = search.strip()
            if product_id is not None:
                query = query.where(Product.id == product_id)
            if cleaned:
                term = f"%{cleaned}%"
                query = query.where(
                    or_(
                        PedeOnProductPublication.display_name.ilike(term),
                        PedeOnProductPublication.description.ilike(term),
                        Product.name.ilike(term),
                        Product.description.ilike(term),
                    )
                )
            if category:
                category_id = db.scalar(
                    select(PedeOnCategory.id).where(
                        PedeOnCategory.store_id == store.id,
                        PedeOnCategory.slug == category,
                        PedeOnCategory.active.is_(True),
                        PedeOnCategory.channel.in_(("online", "shared")),
                    )
                )
                if category_id is None:
                    return cls._page(db, store, categories, [], page, page_size, 0)
                # A publication may use a different category id per channel;
                # apply the final category filter after resolving the channel.
            matching_rows = [
                row
                for row in db.execute(
                    query.order_by(
                        PedeOnProductPublication.sort_order,
                        Product.name,
                        Product.id,
                    )
                ).all()
                if cls._enabled_for(row[0], {cls.ONLINE_CHANNEL})
                and cls._published_for(row[0], cls.ONLINE_CHANNEL)
                and (
                    category is None
                    or cls._channel_category_id(row[0], "online") == category_id
                )
            ]
            total = len(matching_rows)
            rows = matching_rows[(page - 1) * page_size : page * page_size]
            groups_by_publication = cls._public_groups(
                db, store.id, [publication.id for publication, _ in rows], channel="online"
            )
            items = [
                cls._product(
                    publication,
                    product,
                    groups_by_publication.get(publication.id, []),
                    category_id=cls._channel_category_id(publication, "online"),
                )
                for publication, product in rows
            ]
            return cls._page(db, store, categories, items, page, page_size, total)

    @classmethod
    def edge_catalog(cls, db: Session, store: PedeOnStore) -> EdgeCatalogRead:
        """Build the LAN catalog independently from the public online catalog."""
        categories = cls._categories(db, store.id, channel="salon")
        rows = [
            row
            for row in db.execute(
                select(PedeOnProductPublication, Product)
                .join(Product, Product.id == PedeOnProductPublication.product_id)
                .where(
                    PedeOnProductPublication.store_id == store.id,
                    PedeOnProductPublication.available.is_(True),
                    Product.active.is_(True),
                )
                .order_by(
                    PedeOnProductPublication.sort_order,
                    Product.name,
                    Product.id,
                )
            ).all()
            if cls._enabled_for(row[0], cls.LOCAL_CHANNELS)
            and any(cls._available_for(row[0], channel) for channel in cls.LOCAL_CHANNELS)
        ]
        groups = cls._public_groups(
            db, store.id, [publication.id for publication, _ in rows], channel="salon"
        )
        items = []
        for publication, product in rows:
            base = cls._product(
                publication,
                product,
                groups.get(publication.id, []),
                category_id=cls._channel_category_id(publication, "salon"),
            )
            items.append(
                EdgeCatalogProductRead(
                    **base.model_dump(),
                    enabled_channels=sorted(
                        cls._enabled_channels(publication).intersection(
                            cls.LOCAL_CHANNELS
                        )
                    ),
                )
            )
        page = cls._page(db, store, categories, [], 1, max(1, len(items)), 0)
        return EdgeCatalogRead(
            revision=cls.edge_catalog_revision(db, store),
            store=page.store,
            categories=categories,
            items=items,
        )

    @classmethod
    def operational_catalog(cls, db: Session, store: PedeOnStore) -> EdgeCatalogRead:
        """Build the local catalog from explicit PedeOn channel settings.

        ERP products remain the source for stock and fiscal data, while the
        PedeOn publication is the source for local availability, category,
        presentation and channel selection.  This prevents stock categories
        from leaking into the salon and avoids exposing products that were not
        deliberately enabled for a local channel.
        """
        rows = [
            row
            for row in db.execute(
                select(PedeOnProductPublication, Product)
                .join(Product, Product.id == PedeOnProductPublication.product_id)
                .where(
                    PedeOnProductPublication.store_id == store.id,
                    PedeOnProductPublication.available.is_(True),
                    PedeOnProductPublication.category_id.is_not(None),
                    Product.active.is_(True),
                )
                .order_by(
                    PedeOnProductPublication.sort_order,
                    Product.name,
                    Product.id,
                )
            ).all()
            if cls._enabled_for(row[0], cls.LOCAL_CHANNELS)
            and any(cls._available_for(row[0], channel) for channel in cls.LOCAL_CHANNELS)
        ]
        publication_ids = [publication.id for publication, _ in rows]
        groups = cls._public_groups(db, store.id, publication_ids, channel="salon")
        category_ids = {
            cls._channel_category_id(publication, "salon")
            for publication, _ in rows
        }
        categories = [
            category
            for category in cls._categories(db, store.id, channel="salon")
            if category.id in category_ids
        ]
        items = []
        for publication, product in rows:
            base = cls._product(
                publication,
                product,
                groups.get(publication.id, []),
                category_id=cls._channel_category_id(publication, "salon"),
            )
            items.append(
                EdgeCatalogProductRead(
                    **base.model_dump(),
                    enabled_channels=sorted(
                        cls._enabled_channels(publication).intersection(
                            cls.LOCAL_CHANNELS
                        )
                    ),
                )
            )
        page = cls._page(db, store, categories, [], 1, max(1, len(items)), 0)
        return EdgeCatalogRead(
            revision=cls.operational_catalog_revision(db, store),
            store=page.store,
            categories=categories,
            items=items,
        )

    @staticmethod
    def operational_catalog_revision(db: Session, store: PedeOnStore) -> int:
        """Stable revision for changes in the ERP assortment and its prices."""
        products = db.execute(
            select(
                Product.id,
                Product.name,
                Product.category,
                Product.sale_price,
                Product.offer_price,
                Product.active,
                Product.unit,
                Product.barcode,
                Product.internal_code,
            )
            .where(Product.active.is_(True))
            .order_by(Product.id)
        ).all()
        publications = db.execute(
            select(
                PedeOnProductPublication.product_id,
                PedeOnProductPublication.category_id,
                PedeOnProductPublication.available,
                PedeOnProductPublication.availability_rules,
                PedeOnProductPublication.online_price,
                PedeOnProductPublication.display_name,
                PedeOnProductPublication.description,
                PedeOnProductPublication.image_url,
                PedeOnProductPublication.use_product_offer,
                PedeOnProductPublication.sort_order,
            ).where(PedeOnProductPublication.store_id == store.id)
        ).all()
        source = "|".join(
            ":".join(str(value) for value in row) for row in products
        ) + "|publications:" + "|".join(
            ":".join(str(value) for value in row) for row in publications
        ) + f"|store:{store.id}|schema:operational-v3"
        return int.from_bytes(hashlib.sha256(source.encode()).digest()[:8], "big")

    @staticmethod
    def edge_catalog_revision(db: Session, store: PedeOnStore) -> int:
        return int(
            db.scalar(
                select(func.max(PedeOnOutboxEvent.id)).where(
                    PedeOnOutboxEvent.aggregate_type == "catalog",
                    PedeOnOutboxEvent.aggregate_id == str(store.id),
                )
            )
            or 0
        )

    @classmethod
    def quote(cls, slug: str, payload: CartQuoteRequest) -> CartQuoteRead:
        registry = cls._registry(slug)
        with session_for_company(registry.company_code) as db:
            store = cls._active_store(db, registry.tenant_store_id, slug)
            resolved = cls.resolve_cart(db, store, payload.items)
            lines: list[CartQuoteLineRead] = []
            subtotal = Decimal("0")
            for line in resolved:
                subtotal += line.total
                lines.append(
                    CartQuoteLineRead(
                        line_id=line.request.line_id,
                        product_id=line.product.id,
                        name=line.publication.display_name or line.product.name,
                        quantity=line.request.quantity,
                        unit_price=line.unit_price,
                        total=line.total,
                        image_url=line.publication.image_url or line.product.image_url,
                        modifiers=[
                            f"{item.group.name}: {item.option.name}"
                            + (f" × {item.quantity}" if item.quantity != 1 else "")
                            for item in line.modifiers
                        ],
                    )
                )
            subtotal = subtotal.quantize(MONEY, rounding=ROUND_HALF_UP)
            minimum = Decimal(store.minimum_order_amount).quantize(MONEY)
            delivery = None
            if payload.fulfillment_type == "delivery":
                if payload.delivery_address is None:
                    raise ValueError("Informe o endereço para calcular a entrega.")
                delivery = PedeOnDeliveryService(db).quote(
                    store, payload.delivery_address, subtotal
                )
            delivery_fee = delivery.fee if delivery else Decimal("0.00")
            return CartQuoteRead(
                store_slug=slug,
                lines=lines,
                subtotal=subtotal,
                minimum_order_amount=minimum,
                minimum_order_reached=subtotal >= minimum,
                delivery_fee=delivery_fee,
                total=(subtotal + delivery_fee).quantize(MONEY),
                delivery_zone_name=delivery.zone_name if delivery else None,
                estimated_minutes_min=(
                    delivery.estimated_minutes_min if delivery else None
                ),
                estimated_minutes_max=(
                    delivery.estimated_minutes_max if delivery else None
                ),
            )

    @staticmethod
    def _registry(slug: str) -> PedeOnPublicStore:
        with MasterSessionLocal() as master:
            registry = master.scalar(
                select(PedeOnPublicStore).where(
                    PedeOnPublicStore.public_slug == slug,
                    PedeOnPublicStore.active.is_(True),
                )
            )
            if registry is None:
                raise LookupError("Loja PedeOn não encontrada.")
            master.expunge(registry)
            if "pedeon" not in get_enabled_modules_for_company(registry.company_code):
                raise LookupError("Loja PedeOn não encontrada.")
            return registry

    @staticmethod
    def _active_store(db: Session, store_id: int, slug: str) -> PedeOnStore:
        store = db.scalar(
            select(PedeOnStore).where(
                PedeOnStore.id == store_id,
                PedeOnStore.public_slug == slug,
                PedeOnStore.active.is_(True),
            )
        )
        if store is None:
            raise LookupError("Loja PedeOn não encontrada.")
        return store

    @staticmethod
    def _categories(
        db: Session, store_id: int, *, channel: str | None = None
    ) -> list[PublicCategoryRead]:
        channels = (channel, "shared") if channel else None
        return [
            PublicCategoryRead(
                id=item.id,
                name=item.name,
                slug=item.slug,
                description=item.description,
                image_url=item.image_url,
            )
            for item in db.scalars(
                select(PedeOnCategory)
                .where(PedeOnCategory.store_id == store_id, PedeOnCategory.active.is_(True),
                       *([PedeOnCategory.channel.in_(channels)] if channels else []))
                .order_by(PedeOnCategory.sort_order, PedeOnCategory.name)
            )
        ]

    @staticmethod
    def _product(
        publication: PedeOnProductPublication,
        product: Product,
        modifier_groups: list[PublicModifierGroupRead],
        *,
        category_id: int | None = None,
    ) -> PublicProductRead:
        price, on_offer = effective_product_price(product, publication)
        return PublicProductRead(
            product_id=product.id,
            category_id=category_id if category_id is not None else publication.category_id,
            name=publication.display_name or product.name,
            description=publication.description or product.description,
            image_url=publication.image_url or product.image_url,
            price=price,
            normal_price=Decimal(product.sale_price).quantize(MONEY),
            on_offer=on_offer,
            available=publication.available
            and all(
                len(group.options) >= group.minimum_selections
                for group in modifier_groups
            ),
            unit=product.unit,
            modifier_groups=modifier_groups,
        )

    @classmethod
    def _public_groups(
        cls, db: Session, store_id: int, publication_ids: list[int], *, channel: str | None = None
    ) -> dict[int, list[PublicModifierGroupRead]]:
        if not publication_ids:
            return {}
        channels = (channel, "shared") if channel else None
        links = db.execute(
            select(PedeOnProductModifierGroup, PedeOnModifierGroup)
            .join(PedeOnModifierGroup, PedeOnModifierGroup.id == PedeOnProductModifierGroup.group_id)
            .where(
                PedeOnProductModifierGroup.publication_id.in_(publication_ids),
                PedeOnModifierGroup.store_id == store_id,
                PedeOnModifierGroup.active.is_(True),
                *([PedeOnModifierGroup.channel.in_(channels)] if channels else []),
            )
            .order_by(
                PedeOnProductModifierGroup.publication_id,
                PedeOnProductModifierGroup.sort_order,
                PedeOnModifierGroup.sort_order,
            )
        ).all()
        group_ids = {group.id for _, group in links}
        options_by_group: dict[int, list[PedeOnModifierOption]] = {}
        if group_ids:
            for option in db.scalars(
                select(PedeOnModifierOption)
                .where(
                    PedeOnModifierOption.group_id.in_(group_ids),
                    PedeOnModifierOption.active.is_(True),
                )
                .order_by(PedeOnModifierOption.sort_order, PedeOnModifierOption.name)
            ):
                options_by_group.setdefault(option.group_id, []).append(option)
        linked_product_ids = {
            option.product_id
            for group_options in options_by_group.values()
            for option in group_options
            if option.product_id is not None
        }
        linked_products = cls._available_modifier_products(
            db, store_id, linked_product_ids
        )
        result: dict[int, list[PublicModifierGroupRead]] = {}
        for link, group in links:
            result.setdefault(link.publication_id, []).append(
                PublicModifierGroupRead(
                    id=group.id,
                    name=group.name,
                    description=group.description,
                    minimum_selections=group.minimum_selections,
                    maximum_selections=group.maximum_selections,
                    kind=group.kind,
                    options=[
                        PublicModifierOptionRead(
                            id=option.id,
                            name=option.name,
                            price_delta=(
                                effective_product_price(
                                    linked_products[option.product_id][1],
                                    linked_products[option.product_id][0],
                                )[0]
                                if option.product_id in linked_products
                                else option.price_delta
                            ),
                            available_quantity=(
                                int(linked_products[option.product_id][1].stock_quantity)
                                if option.product_id in linked_products
                                else None
                            ),
                            minimum_quantity=option.minimum_quantity,
                            maximum_quantity=option.maximum_quantity,
                        )
                        for option in options_by_group.get(group.id, [])
                        if option.product_id is None
                        or option.product_id in linked_products
                    ],
                )
            )
        return result

    @staticmethod
    def _channel_category_id(
        publication: PedeOnProductPublication, channel: str
    ) -> int | None:
        configured = (publication.availability_rules or {}).get(
            "channel_category_ids", {}
        )
        return configured.get(channel) or publication.category_id

    @classmethod
    def resolve_cart(
        cls,
        db: Session,
        store: PedeOnStore,
        requests: list,
        *,
        channel: str = ONLINE_CHANNEL,
    ) -> list[ResolvedCartLine]:
        product_ids = {item.product_id for item in requests}
        rows = db.execute(
            select(PedeOnProductPublication, Product)
            .join(Product, Product.id == PedeOnProductPublication.product_id)
            .where(
                PedeOnProductPublication.store_id == store.id,
                PedeOnProductPublication.product_id.in_(product_ids),
                Product.active.is_(True),
            )
        ).all()
        rows = [row for row in rows if cls._enabled_for(row[0], {channel}) and cls._available_for(row[0], channel)]
        if channel == cls.ONLINE_CHANNEL:
            rows = [row for row in rows if cls._published_for(row[0], channel)]
        if channel in cls.LOCAL_CHANNELS:
            published_product_ids = {product.id for _, product in rows}
            operational_products = db.scalars(
                select(Product).where(
                    Product.id.in_(product_ids - published_product_ids),
                    Product.active.is_(True),
                )
            ).all()
            rows.extend((None, product) for product in operational_products)
        by_product = {product.id: (publication, product) for publication, product in rows}
        if product_ids - set(by_product):
            raise ValueError(
                "Um ou mais itens não estão disponíveis. Atualize o cardápio e tente novamente."
            )
        publication_ids = [
            publication.id
            for publication, _ in by_product.values()
            if publication is not None
        ]
        links_by_publication: dict[int, set[int]] = {}
        for publication_id, group_id in db.execute(
            select(
                PedeOnProductModifierGroup.publication_id,
                PedeOnProductModifierGroup.group_id,
            ).where(PedeOnProductModifierGroup.publication_id.in_(publication_ids))
        ):
            links_by_publication.setdefault(publication_id, set()).add(group_id)
        group_ids = set().union(*links_by_publication.values()) if links_by_publication else set()
        groups = {
            group.id: group
            for group in db.scalars(
                select(PedeOnModifierGroup).where(
                    PedeOnModifierGroup.id.in_(group_ids),
                    PedeOnModifierGroup.active.is_(True),
                    PedeOnModifierGroup.channel.in_(
                        ("online", "shared")
                        if channel == cls.ONLINE_CHANNEL
                        else ("salon", "shared")
                    ),
                )
            )
        } if group_ids else {}
        options = {
            option.id: option
            for option in db.scalars(
                select(PedeOnModifierOption).where(
                    PedeOnModifierOption.group_id.in_(groups),
                    PedeOnModifierOption.active.is_(True),
                )
            )
        } if groups else {}
        linked_product_ids = {
            option.product_id
            for option in options.values()
            if option.product_id is not None
        }
        linked_products = cls._available_modifier_products(
            db, store.id, linked_product_ids
        )
        linked_stock_demand: dict[int, Decimal] = {}
        resolved: list[ResolvedCartLine] = []
        for request in requests:
            publication, product = by_product[request.product_id]
            linked_group_ids = (
                links_by_publication.get(publication.id, set())
                if publication is not None
                else set()
            )
            selected_by_group: dict[int, list[tuple[PedeOnModifierOption, Decimal]]] = {}
            seen_options: set[int] = set()
            for selection in request.modifiers:
                if selection.option_id in seen_options:
                    raise ValueError("Uma opção foi informada mais de uma vez.")
                seen_options.add(selection.option_id)
                option = options.get(selection.option_id)
                if option is None or option.group_id not in linked_group_ids:
                    raise ValueError("Uma opção escolhida não pertence a este produto.")
                if selection.quantity < option.minimum_quantity or (
                    option.maximum_quantity is not None
                    and selection.quantity > option.maximum_quantity
                ):
                    raise ValueError(
                        f"A quantidade escolhida para {option.name} está fora do limite permitido."
                    )
                if (
                    option.product_id is not None
                    and option.product_id not in linked_products
                ):
                    raise ValueError(
                        f"{option.name} não está disponível no momento."
                    )
                selected_by_group.setdefault(option.group_id, []).append(
                    (option, selection.quantity)
                )
                if option.product_id is not None:
                    linked_stock_demand[option.product_id] = (
                        linked_stock_demand.get(option.product_id, Decimal("0"))
                        + (Decimal(selection.quantity) * Decimal(request.quantity))
                    )
            line_modifiers: list[ResolvedModifier] = []
            for group_id in linked_group_ids:
                group = groups.get(group_id)
                if group is None:
                    continue
                selected = selected_by_group.get(group_id, [])
                selected_count = sum((quantity for _, quantity in selected), Decimal("0"))
                if selected_count < group.minimum_selections:
                    raise ValueError(f"Escolha ao menos {group.minimum_selections} opção(ões) em {group.name}.")
                if group.maximum_selections is not None and selected_count > group.maximum_selections:
                    raise ValueError(f"Escolha no máximo {group.maximum_selections} opção(ões) em {group.name}.")
                for option, quantity in selected:
                    line_modifiers.append(
                        ResolvedModifier(
                            group=group,
                            option=option,
                            quantity=quantity,
                            unit_price=(
                                effective_product_price(
                                    linked_products[option.product_id][1],
                                    linked_products[option.product_id][0],
                                )[0]
                                if option.product_id in linked_products
                                else Decimal(option.price_delta).quantize(MONEY)
                            ),
                        )
                    )
            base_price, _ = effective_product_price(product, publication)
            resolved.append(
                ResolvedCartLine(
                    request=request,
                    publication=publication,
                    product=product,
                    base_unit_price=base_price,
                    modifiers=tuple(line_modifiers),
                )
            )
        from app.modules.pedeon.application.inventory_service import (
            inventory_policy_for_store,
        )

        inventory_policy = inventory_policy_for_store(db, store.id)
        for product_id, demanded in linked_stock_demand.items():
            product = linked_products[product_id][1]
            if (
                inventory_policy == "strict_block"
                and demanded > Decimal(product.stock_quantity)
            ):
                raise ValueError(
                    f"Estoque insuficiente para {product.name}. "
                    f"Disponível: {product.stock_quantity} {product.unit}."
                )
        return resolved

    @staticmethod
    def _available_modifier_products(
        db: Session, store_id: int, product_ids: set[int]
    ) -> dict[int, tuple[PedeOnProductPublication | None, Product]]:
        if not product_ids:
            return {}
        rows = db.execute(
            select(PedeOnProductPublication, Product)
            .select_from(Product)
            .outerjoin(
                PedeOnProductPublication,
                and_(
                    PedeOnProductPublication.product_id == Product.id,
                    PedeOnProductPublication.store_id == store_id,
                ),
            )
            .where(
                Product.id.in_(product_ids),
                Product.active.is_(True),
                Product.stock_quantity > 0,
                or_(
                    PedeOnProductPublication.id.is_(None),
                    PedeOnProductPublication.available.is_(True),
                ),
            )
        ).all()
        return {product.id: (publication, product) for publication, product in rows}

    @staticmethod
    def _page(
        db: Session,
        store: PedeOnStore,
        categories: list[PublicCategoryRead],
        items: list[PublicProductRead],
        page: int,
        page_size: int,
        total: int,
    ) -> PublicCatalogPageRead:
        payment_methods = []
        for item in db.scalars(
                select(PedeOnPaymentConfiguration)
                .where(
                    PedeOnPaymentConfiguration.store_id == store.id,
                    PedeOnPaymentConfiguration.enabled.is_(True),
                    PedeOnPaymentConfiguration.method.in_(
                        [
                            "manual_pix",
                            "infinitepay_pix",
                            "credit_card_on_delivery",
                            "debit_card_on_delivery",
                            "pay_at_pickup",
                        ]
                    ),
                )
                .order_by(PedeOnPaymentConfiguration.id)
            ):
            configuration = item.public_configuration or {}
            if item.method in {"credit_card_on_delivery", "debit_card_on_delivery"}:
                fulfillment_types = ["delivery"]
            elif item.method == "pay_at_pickup":
                fulfillment_types = []
                if configuration.get("pickup_enabled", True):
                    fulfillment_types.append("pickup")
                if configuration.get(
                    "delivery_methods", configuration.get("accepted_methods", [])
                ):
                    fulfillment_types.append("delivery")
            else:
                fulfillment_types = [
                    fulfillment
                    for fulfillment in ("pickup", "delivery")
                    if configuration.get(f"{fulfillment}_enabled", True)
                ]
            if fulfillment_types:
                payment_methods.append(
                    PublicPaymentMethodRead(
                        method=item.method,
                        display_name=item.display_name or item.method,
                        fulfillment_types=fulfillment_types,
                        local_methods=(
                            configuration.get(
                                "delivery_methods",
                                configuration.get("accepted_methods", []),
                            )
                            if item.method == "pay_at_pickup"
                            and "delivery" in fulfillment_types
                            else configuration.get(
                                "accepted_methods",
                                ["cash", "pix", "credit_card", "debit_card"],
                            )
                            if item.method == "pay_at_pickup"
                            else []
                        ),
                    )
                )
        delivery_operation = (store.settings or {}).get("delivery_operation", {})
        delivery_fee = (
            delivery_operation.get("fixed_fee_amount")
            if delivery_operation.get("pricing_mode") == "fixed"
            else None
        )
        return PublicCatalogPageRead(
            store=PublicStoreRead(
                slug=store.public_slug,
                display_name=store.display_name,
                description=store.description,
                logo_url=store.logo_url,
                cover_url=store.cover_url,
                accent_color=(store.settings or {}).get("accent_color", "#075E6F"),
                dark_mode=(store.settings or {}).get("dark_mode", False),
                delivery_fee=delivery_fee,
                delivery_minutes_min=delivery_operation.get("preparation_minutes_min"),
                delivery_minutes_max=delivery_operation.get("preparation_minutes_max"),
                accepting_orders=store_is_accepting_orders(store),
                experience_mode=store.experience_mode,
                fulfillment_options=store.fulfillment_options or [],
                minimum_order_amount=store.minimum_order_amount,
                payment_methods=payment_methods,
            ),
            categories=categories,
            items=items,
            page=page,
            page_size=page_size,
            total=total,
            total_pages=max(1, ceil(total / page_size)),
        )

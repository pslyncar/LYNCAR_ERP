import re
import unicodedata
from datetime import datetime, timezone
from math import ceil
from uuid import uuid4

from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.models.product import Product
from app.modules.pedeon.application.schemas import (
    CatalogPageRead,
    CatalogProductRead,
    CategoryCreate,
    CategoryRead,
    CategoryReorder,
    CategoryUpdate,
    ModifierGroupInput,
    ModifierGroupRead,
    ModifierOptionRead,
    PublicationUpdate,
)
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnCategory,
    PedeOnModifierGroup,
    PedeOnModifierOption,
    PedeOnOutboxEvent,
    PedeOnProductModifierGroup,
    PedeOnProductPublication,
    PedeOnStore,
)


def _slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", normalized.lower()).strip("-") or "categoria"


class PedeOnCatalogService:
    def __init__(self, db: Session):
        self.db = db

    def list_catalog(self, search: str, page: int, page_size: int) -> CatalogPageRead:
        store = self._store()
        query = select(Product).where(Product.active.is_(True))
        cleaned = search.strip()
        if cleaned:
            term = f"%{cleaned}%"
            query = query.where(
                or_(
                    Product.name.ilike(term),
                    Product.internal_code.ilike(term),
                    Product.barcode.ilike(term),
                )
            )
        total = self.db.scalar(select(func.count()).select_from(query.subquery())) or 0
        products = self.db.scalars(
            query.order_by(Product.name, Product.id)
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        publications = {
            item.product_id: item
            for item in self.db.scalars(
                select(PedeOnProductPublication).where(
                    PedeOnProductPublication.store_id == store.id,
                    PedeOnProductPublication.product_id.in_([p.id for p in products]),
                )
            )
        } if products else {}
        publication_ids = [item.id for item in publications.values()]
        linked_groups: dict[int, list[int]] = {}
        if publication_ids:
            for publication_id, group_id in self.db.execute(
                select(
                    PedeOnProductModifierGroup.publication_id,
                    PedeOnProductModifierGroup.group_id,
                )
                .where(PedeOnProductModifierGroup.publication_id.in_(publication_ids))
                .order_by(PedeOnProductModifierGroup.sort_order)
            ):
                linked_groups.setdefault(publication_id, []).append(group_id)
        return CatalogPageRead(
            items=[
                self._product_read(
                    product,
                    publications.get(product.id),
                    linked_groups.get(publications[product.id].id, [])
                    if product.id in publications
                    else [],
                )
                for product in products
            ],
            categories=self._categories(store.id),
            modifier_groups=self._modifier_groups(store.id),
            page=page,
            page_size=page_size,
            total=total,
            total_pages=max(1, ceil(total / page_size)),
        )

    def create_category(self, payload: CategoryCreate) -> CategoryRead:
        store = self._store()
        base_slug = _slugify(payload.name)
        slug = base_slug
        suffix = 2
        while self.db.scalar(
            select(PedeOnCategory.id).where(
                PedeOnCategory.store_id == store.id,
                PedeOnCategory.slug == slug,
            )
        ):
            slug = f"{base_slug}-{suffix}"
            suffix += 1
        next_order = (
            self.db.scalar(
                select(func.max(PedeOnCategory.sort_order)).where(
                    PedeOnCategory.store_id == store.id
                )
            )
            or 0
        ) + 10
        category = PedeOnCategory(
            store_id=store.id,
            name=payload.name.strip(),
            slug=slug,
            channel=payload.channel,
            description=(payload.description or "").strip() or None,
            active=payload.active,
            sort_order=next_order,
        )
        self.db.add(category)
        self.db.flush()
        self._event(store.id, "pedeon.catalog.category.created")
        self.db.commit()
        self.db.refresh(category)
        return CategoryRead.model_validate(category, from_attributes=True)

    def update_category(self, category_id: int, payload: CategoryUpdate) -> CategoryRead:
        store = self._store()
        category = self._category(store.id, category_id)
        category.name = payload.name.strip()
        category.channel = payload.channel
        category.description = (payload.description or "").strip() or None
        category.active = payload.active
        category.sort_order = payload.sort_order
        self._event(store.id, "pedeon.catalog.category.updated")
        self.db.commit()
        self.db.refresh(category)
        return CategoryRead.model_validate(category, from_attributes=True)

    def reorder_categories(self, payload: CategoryReorder) -> list[CategoryRead]:
        store = self._store()
        categories = self.db.scalars(
            select(PedeOnCategory).where(PedeOnCategory.store_id == store.id)
        ).all()
        by_id = {category.id: category for category in categories}
        if set(payload.category_ids) != set(by_id):
            raise ValueError(
                "A lista precisa conter todas as categorias atuais da loja. Atualize a tela e tente novamente."
            )
        for index, category_id in enumerate(payload.category_ids, start=1):
            by_id[category_id].sort_order = index * 10
        self._event(store.id, "pedeon.catalog.categories.reordered")
        self.db.commit()
        return self._categories(store.id)

    def delete_category(self, category_id: int) -> None:
        store = self._store()
        category = self._category(store.id, category_id)
        for publication in self.db.scalars(
            select(PedeOnProductPublication).where(
                PedeOnProductPublication.category_id == category.id
            )
        ):
            publication.category_id = None
        self.db.delete(category)
        self._event(store.id, "pedeon.catalog.category.deleted")
        self.db.commit()

    def create_modifier_group(self, payload: ModifierGroupInput) -> ModifierGroupRead:
        store = self._store()
        group = PedeOnModifierGroup(
            store_id=store.id,
            code=f"group-{uuid4().hex[:12]}",
            channel=payload.channel,
            kind=payload.kind,
        )
        self.db.add(group)
        self._apply_modifier_group(group, payload)
        self._event(store.id, "pedeon.catalog.modifier_group.created")
        self.db.commit()
        return self._modifier_group_read(group)

    def update_modifier_group(
        self, group_id: int, payload: ModifierGroupInput
    ) -> ModifierGroupRead:
        store = self._store()
        group = self._modifier_group(store.id, group_id)
        self._apply_modifier_group(group, payload)
        self._event(store.id, "pedeon.catalog.modifier_group.updated")
        self.db.commit()
        return self._modifier_group_read(group)

    def delete_modifier_group(self, group_id: int) -> None:
        store = self._store()
        group = self._modifier_group(store.id, group_id)
        self.db.delete(group)
        self._event(store.id, "pedeon.catalog.modifier_group.deleted")
        self.db.commit()

    def update_publication(
        self, product_id: int, payload: PublicationUpdate
    ) -> CatalogProductRead:
        store = self._store()
        product = self.db.get(Product, product_id)
        if product is None or not product.active:
            raise LookupError("Produto ativo não encontrado.")
        category_ids = {
            "online": payload.online_category_id,
            "salon": payload.salon_category_id,
        }
        for category_id in category_ids.values():
            if category_id is not None:
                self._category(store.id, category_id)
        if payload.category_id is not None:
            self._category(store.id, payload.category_id)
        effective_price = payload.online_price
        if effective_price is None:
            effective_price = product.offer_price if payload.use_product_offer and product.offer_price is not None else product.sale_price
        if payload.published and effective_price <= 0:
            raise ValueError("Informe um preço maior que zero antes de publicar.")
        publication = self.db.scalar(
            select(PedeOnProductPublication).where(
                PedeOnProductPublication.store_id == store.id,
                PedeOnProductPublication.product_id == product.id,
            )
        )
        if publication is None:
            publication = PedeOnProductPublication(store_id=store.id, product_id=product.id)
            self.db.add(publication)
        data = payload.model_dump(
            exclude={
                "modifier_group_ids", "online_modifier_group_ids",
                "salon_modifier_group_ids", "enabled_channels",
                "published_channels", "available_channels",
                "production_station_code", "online_category_id", "salon_category_id",
            }
        )
        if payload.category_id is None:
            data["category_id"] = payload.online_category_id or payload.salon_category_id
        for field, value in data.items():
            setattr(publication, field, value)
        publication.display_name = (payload.display_name or "").strip() or None
        publication.description = (payload.description or "").strip() or None
        publication.image_url = (payload.image_url or "").strip() or None
        publication.availability_rules = {
            **(publication.availability_rules or {}),
            "enabled_channels": payload.enabled_channels,
            "published_channels": payload.published_channels,
            "available_channels": payload.available_channels,
            "production_station_code": payload.production_station_code,
            "channel_category_ids": {
                channel: category_id
                for channel, category_id in category_ids.items()
                if category_id is not None
            },
            "channel_modifier_group_ids": {
                "online": payload.online_modifier_group_ids or payload.modifier_group_ids,
                "salon": payload.salon_modifier_group_ids or payload.modifier_group_ids,
            },
        }
        publication.updated_at = datetime.now(timezone.utc)
        self.db.flush()
        # The relation is the product-level catalog link.  Keep the union of
        # the channel-specific questions here; the public catalog filters the
        # linked questions by the requested channel.
        group_ids = list(dict.fromkeys(
            [
                *payload.modifier_group_ids,
                *payload.online_modifier_group_ids,
                *payload.salon_modifier_group_ids,
            ]
        ))
        if group_ids:
            found = set(
                self.db.scalars(
                    select(PedeOnModifierGroup.id).where(
                        PedeOnModifierGroup.store_id == store.id,
                        PedeOnModifierGroup.id.in_(group_ids),
                    )
                )
            )
            if found != set(group_ids):
                raise ValueError("Um ou mais grupos de adicionais não pertencem à loja.")
        self.db.execute(
            delete(PedeOnProductModifierGroup).where(
                PedeOnProductModifierGroup.publication_id == publication.id
            )
        )
        for sort_order, group_id in enumerate(group_ids):
            self.db.add(
                PedeOnProductModifierGroup(
                    publication_id=publication.id,
                    group_id=group_id,
                    sort_order=sort_order,
                )
            )
        self._event(store.id, "pedeon.catalog.product.updated")
        self.db.commit()
        self.db.refresh(publication)
        return self._product_read(product, publication, group_ids)

    def _store(self) -> PedeOnStore:
        store = self.db.scalar(select(PedeOnStore).order_by(PedeOnStore.id).limit(1))
        if store is None:
            raise LookupError("Configure a loja PedeOn antes de publicar produtos.")
        return store

    def _category(self, store_id: int, category_id: int) -> PedeOnCategory:
        category = self.db.scalar(
            select(PedeOnCategory).where(
                PedeOnCategory.id == category_id,
                PedeOnCategory.store_id == store_id,
            )
        )
        if category is None:
            raise LookupError("Categoria não encontrada.")
        return category

    def _modifier_group(self, store_id: int, group_id: int) -> PedeOnModifierGroup:
        group = self.db.scalar(
            select(PedeOnModifierGroup).where(
                PedeOnModifierGroup.id == group_id,
                PedeOnModifierGroup.store_id == store_id,
            )
        )
        if group is None:
            raise LookupError("Grupo de adicionais não encontrado.")
        return group

    def _categories(self, store_id: int) -> list[CategoryRead]:
        return [
            CategoryRead.model_validate(item, from_attributes=True)
            for item in self.db.scalars(
                select(PedeOnCategory)
                .where(PedeOnCategory.store_id == store_id)
                .order_by(PedeOnCategory.sort_order, PedeOnCategory.name)
            )
        ]

    def _modifier_groups(self, store_id: int) -> list[ModifierGroupRead]:
        groups = self.db.scalars(
            select(PedeOnModifierGroup)
            .where(PedeOnModifierGroup.store_id == store_id)
            .order_by(PedeOnModifierGroup.sort_order, PedeOnModifierGroup.name)
        ).all()
        return [self._modifier_group_read(group) for group in groups]

    def _modifier_group_read(self, group: PedeOnModifierGroup) -> ModifierGroupRead:
        options = self.db.scalars(
            select(PedeOnModifierOption)
            .where(PedeOnModifierOption.group_id == group.id)
            .order_by(PedeOnModifierOption.sort_order, PedeOnModifierOption.name)
        ).all()
        return ModifierGroupRead(
            id=group.id,
            code=group.code,
            channel=group.channel,
            kind=group.kind,
            name=group.name,
            description=group.description,
            minimum_selections=group.minimum_selections,
            maximum_selections=group.maximum_selections,
            sort_order=group.sort_order,
            active=group.active,
            options=[
                ModifierOptionRead(
                    id=option.id,
                    code=option.code,
                    name=option.name,
                    price_delta=option.price_delta,
                    product_id=option.product_id,
                    sort_order=option.sort_order,
                    active=option.active,
                    minimum_quantity=option.minimum_quantity,
                    maximum_quantity=option.maximum_quantity,
                )
                for option in options
            ],
        )

    def _apply_modifier_group(
        self, group: PedeOnModifierGroup, payload: ModifierGroupInput
    ) -> None:
        group.name = payload.name.strip()
        group.channel = payload.channel
        group.kind = payload.kind
        group.description = (payload.description or "").strip() or None
        group.minimum_selections = payload.minimum_selections
        group.maximum_selections = payload.maximum_selections
        group.sort_order = payload.sort_order
        group.active = payload.active
        is_new = group.id is None
        if is_new:
            self.db.flush()
        else:
            self.db.execute(
                delete(PedeOnModifierOption).where(
                    PedeOnModifierOption.group_id == group.id
                )
            )
        for index, item in enumerate(payload.options):
            group_option = PedeOnModifierOption(
                group_id=group.id,
                code=f"option-{uuid4().hex[:12]}",
                name=item.name.strip(),
                price_delta=item.price_delta,
                product_id=item.product_id,
                sort_order=item.sort_order or index,
                active=item.active,
                minimum_quantity=item.minimum_quantity,
                maximum_quantity=item.maximum_quantity,
            )
            self.db.add(group_option)

    def _product_read(
        self,
        product: Product,
        publication: PedeOnProductPublication | None,
        modifier_group_ids: list[int] | None = None,
    ) -> CatalogProductRead:
        return CatalogProductRead(
            product_id=product.id,
            publication_id=publication.id if publication else None,
            product_name=product.name,
            internal_code=product.internal_code,
            barcode=product.barcode,
            product_image_url=product.image_url,
            product_description=product.description,
            sale_price=product.sale_price,
            offer_price=product.offer_price,
            stock_quantity=product.stock_quantity,
            unit=product.unit,
            product_active=product.active,
            category_id=publication.category_id if publication else None,
            display_name=publication.display_name if publication else None,
            description=publication.description if publication else None,
            image_url=publication.image_url if publication else None,
            online_price=publication.online_price if publication else None,
            published=publication.published if publication else False,
            available=publication.available if publication else True,
            use_product_offer=publication.use_product_offer if publication else True,
            fulfillment_mode=publication.fulfillment_mode if publication else "inherit",
            print_policy=publication.print_policy if publication else "inherit",
            enabled_channels=(publication.availability_rules or {}).get(
                "enabled_channels", ["pedeon_online"]
            ) if publication else ["pedeon_online"],
            published_channels=(publication.availability_rules or {}).get(
                "published_channels", ["pedeon_online"] if publication and publication.published else []
            ) if publication else [],
            available_channels=(publication.availability_rules or {}).get(
                "available_channels", ["pedeon_online", "onsite_qr", "onsite_waiter", "pdv_counter"] if publication and publication.available else []
            ) if publication else [],
            online_category_id=(publication.availability_rules or {}).get(
                "channel_category_ids", {}
            ).get("online") if publication else None,
            salon_category_id=(publication.availability_rules or {}).get(
                "channel_category_ids", {}
            ).get("salon") if publication else None,
            online_modifier_group_ids=(publication.availability_rules or {}).get(
                "channel_modifier_group_ids", {}
            ).get("online", modifier_group_ids or []) if publication else [],
            salon_modifier_group_ids=(publication.availability_rules or {}).get(
                "channel_modifier_group_ids", {}
            ).get("salon", modifier_group_ids or []) if publication else [],
            production_station_code=(publication.availability_rules or {}).get(
                "production_station_code"
            ) if publication else None,
            sort_order=publication.sort_order if publication else 0,
            modifier_group_ids=modifier_group_ids or [],
        )

    def _event(self, store_id: int, event_type: str) -> None:
        self.db.add(
            PedeOnOutboxEvent(
                event_key=str(uuid4()),
                aggregate_type="catalog",
                aggregate_id=str(store_id),
                event_type=event_type,
                payload={"source": "erp_catalog"},
            )
        )

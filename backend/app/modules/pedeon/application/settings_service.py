from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.pdv_terminal import PdvTerminal
from app.models.pedeon_public_store import PedeOnPublicStore
from app.modules.pedeon.application.schemas import (
    DeliveryCardUpdate,
    DeliveryOperationUpdate,
    DeliveryZoneInput,
    DeliveryZoneRead,
    FulfillmentStationInput,
    FulfillmentStationRead,
    InfinitePayUpdate,
    ManualPixUpdate,
    PickupPaymentUpdate,
    PedeOnSettingsRead,
    PaymentSettingsRead,
    StoreSettingsRead,
    StoreSettingsUpdate,
    TerminalPermissionRead,
    TerminalPermissionUpdate,
)
from app.modules.pedeon.application.delivery_service import PedeOnDeliveryService
from app.modules.pedeon.domain.lifecycle import TerminalCapability
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnOutboxEvent,
    PedeOnPaymentConfiguration,
    PedeOnStore,
    PedeOnFulfillmentStation,
    PedeOnEdgeNode,
    PedeOnTerminalPermission,
)


class PedeOnSettingsService:
    def __init__(self, db: Session):
        self.db = db

    def get_settings(self) -> PedeOnSettingsRead:
        store = self._ensure_store()
        self.db.commit()
        self.db.refresh(store)
        return self._settings_read(store)

    def update_store(
        self, company_code: str, payload: StoreSettingsUpdate
    ) -> PedeOnSettingsRead:
        store = self._ensure_store()
        master_db = MasterSessionLocal()
        try:
            registry = master_db.scalar(
                select(PedeOnPublicStore).where(
                    PedeOnPublicStore.company_code == company_code
                )
            )
            owner = master_db.scalar(
                select(PedeOnPublicStore).where(
                    PedeOnPublicStore.public_slug == payload.public_slug,
                    PedeOnPublicStore.company_code != company_code,
                )
            )
            if owner is not None:
                raise ValueError("Este endereço já está sendo usado por outra loja.")
            if registry is None:
                registry = PedeOnPublicStore(
                    company_code=company_code,
                    public_slug=payload.public_slug,
                    tenant_store_id=store.id,
                    display_name=payload.display_name,
                    active=payload.active,
                )
                master_db.add(registry)
            else:
                registry.public_slug = payload.public_slug
                registry.tenant_store_id = store.id
                registry.display_name = payload.display_name
                registry.active = payload.active
                registry.updated_at = datetime.now(timezone.utc)
            # O flush adquire a unicidade global antes de alterar o tenant.
            master_db.flush()
            values = payload.model_dump()
            inventory_policy = values.pop("inventory_policy")
            accent_color = values.pop("accent_color")
            dark_mode = values.pop("dark_mode")
            for field, value in values.items():
                setattr(store, field, value)
            settings = dict(store.settings or {})
            settings["inventory_policy"] = inventory_policy
            settings["accent_color"] = accent_color
            settings["dark_mode"] = dark_mode
            store.settings = settings
            store.updated_at = datetime.now(timezone.utc)
            self._enqueue("store", store.id, "pedeon.store.settings.updated")
            self.db.commit()
            master_db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            master_db.rollback()
            raise ValueError("Este endereço já está sendo usado por outra loja.") from exc
        except Exception:
            self.db.rollback()
            master_db.rollback()
            raise
        finally:
            master_db.close()
        self.db.refresh(store)
        return self._settings_read(store)

    def update_manual_pix(self, payload: ManualPixUpdate) -> PedeOnSettingsRead:
        store = self._ensure_store()
        config = self._payment_config(store.id, "manual_pix")
        config.enabled = payload.enabled
        config.display_name = "Pix manual"
        config.public_configuration = {
            "key_type": payload.key_type,
            "pix_key": payload.pix_key.strip(),
            "recipient_name": payload.recipient_name.strip(),
            "instructions": (payload.instructions or "").strip(),
            "pickup_enabled": payload.pickup_enabled,
            "delivery_enabled": payload.delivery_enabled,
        }
        # Pix manual nunca confirma nem aceita pedido automaticamente.
        config.auto_accept_after_confirmation = False
        config.updated_at = datetime.now(timezone.utc)
        self._enqueue("store", store.id, "pedeon.payment.manual_pix.updated")
        self.db.commit()
        return self._settings_read(store)

    def update_infinitepay(self, payload: InfinitePayUpdate) -> PedeOnSettingsRead:
        store = self._ensure_store()
        config = self._payment_config(store.id, "infinitepay_pix")
        config.enabled = payload.enabled
        config.display_name = "Pix InfinitePay"
        config.public_configuration = {
            "handle": payload.handle.strip(),
            "pickup_enabled": payload.pickup_enabled,
            "delivery_enabled": payload.delivery_enabled,
        }
        config.auto_accept_after_confirmation = payload.auto_accept_after_confirmation
        config.updated_at = datetime.now(timezone.utc)
        self._enqueue("store", store.id, "pedeon.payment.infinitepay.updated")
        self.db.commit()
        return self._settings_read(store)

    def update_delivery_card(self, payload: DeliveryCardUpdate) -> PedeOnSettingsRead:
        store = self._ensure_store()
        for method, enabled, label in (
            ("credit_card_on_delivery", payload.credit_enabled, "Crédito na entrega"),
            ("debit_card_on_delivery", payload.debit_enabled, "Débito na entrega"),
        ):
            config = self._payment_config(store.id, method)
            config.enabled = enabled
            config.display_name = label
            config.public_configuration = {"requires_delivery": True}
            config.auto_accept_after_confirmation = False
            config.updated_at = datetime.now(timezone.utc)
        local_config = self._payment_config(store.id, "pay_at_pickup")
        local_public = dict(local_config.public_configuration or {})
        delivery_methods = [
            method
            for method, enabled in (
                ("cash", payload.cash_enabled),
                ("pix", payload.pix_enabled),
                ("credit_card", payload.credit_enabled),
                ("debit_card", payload.debit_enabled),
            )
            if enabled
        ]
        local_public["delivery_methods"] = delivery_methods
        local_config.enabled = local_config.enabled or bool(delivery_methods)
        local_config.public_configuration = local_public
        local_config.updated_at = datetime.now(timezone.utc)
        self._enqueue("store", store.id, "pedeon.payment.delivery_card.updated")
        self.db.commit()
        return self._settings_read(store)

    def update_pickup_payment(self, payload: PickupPaymentUpdate) -> PedeOnSettingsRead:
        store = self._ensure_store()
        config = self._payment_config(store.id, "pay_at_pickup")
        config.enabled = payload.enabled
        config.display_name = "Pagar no local"
        current = dict(config.public_configuration or {})
        config.public_configuration = {
            "requires_pickup": False,
            "accepted_methods": payload.accepted_methods,
            "delivery_methods": current.get("delivery_methods", []),
        }
        config.auto_accept_after_confirmation = False
        config.updated_at = datetime.now(timezone.utc)
        self._enqueue("store", store.id, "pedeon.payment.pickup.updated")
        self.db.commit()
        return self._settings_read(store)

    def update_delivery_operation(
        self, payload: DeliveryOperationUpdate
    ) -> PedeOnSettingsRead:
        store = self._ensure_store()
        settings = dict(store.settings or {})
        settings["delivery_operation"] = payload.model_dump(mode="json")
        store.settings = settings
        store.updated_at = datetime.now(timezone.utc)
        self._enqueue("store", store.id, "pedeon.delivery.operation.updated")
        self.db.commit()
        self.db.refresh(store)
        return self._settings_read(store)

    def update_terminal(
        self, terminal_id: int, payload: TerminalPermissionUpdate
    ) -> PedeOnSettingsRead:
        store = self._ensure_store()
        device = self.db.scalar(
            select(PedeOnEdgeNode).where(
                PedeOnEdgeNode.id == terminal_id,
                PedeOnEdgeNode.store_id == store.id,
            )
        )
        if device is not None:
            device.device_role = payload.device_role
            device.active = payload.enabled
            device.updated_at = datetime.now(timezone.utc)
            self._enqueue("edge", device.id, "pedeon.device.updated")
            self.db.commit()
            return self._settings_read(store)
        terminal = self.db.get(PdvTerminal, terminal_id)
        if terminal is None:
            raise LookupError("Dispositivo PedeOn não encontrado.")
        permission = self.db.scalar(
            select(PedeOnTerminalPermission).where(
                PedeOnTerminalPermission.store_id == store.id,
                PedeOnTerminalPermission.pdv_terminal_id == terminal_id,
            )
        )
        if permission is None:
            permission = PedeOnTerminalPermission(
                store_id=store.id,
                pdv_terminal_id=terminal_id,
            )
            self.db.add(permission)
        permission.enabled = payload.enabled
        permission.capabilities = [item.value for item in payload.capabilities]
        permission.notification_mode = payload.notification_mode
        permission.priority = payload.priority
        permission.updated_at = datetime.now(timezone.utc)
        self._enqueue("terminal", terminal_id, "pedeon.terminal.permission.updated")
        self.db.commit()
        return self._settings_read(store)

    def create_delivery_zone(self, payload: DeliveryZoneInput) -> DeliveryZoneRead:
        store = self._ensure_store()
        return PedeOnDeliveryService(self.db).create(store.id, payload)

    def update_delivery_zone(
        self, zone_id: int, payload: DeliveryZoneInput
    ) -> DeliveryZoneRead:
        store = self._ensure_store()
        return PedeOnDeliveryService(self.db).update(store.id, zone_id, payload)

    def delete_delivery_zone(self, zone_id: int) -> None:
        store = self._ensure_store()
        PedeOnDeliveryService(self.db).delete(store.id, zone_id)

    def create_station(
        self, payload: FulfillmentStationInput
    ) -> FulfillmentStationRead:
        store = self._ensure_store()
        if self._station_by_code(store.id, payload.code) is not None:
            raise ValueError("Já existe uma estação com este código.")
        station = PedeOnFulfillmentStation(store_id=store.id)
        self._apply_station(station, payload)
        self.db.add(station)
        self._enqueue("station", 0, "pedeon.station.created")
        self.db.commit()
        self.db.refresh(station)
        return FulfillmentStationRead.model_validate(station)

    def update_station(
        self, station_id: int, payload: FulfillmentStationInput
    ) -> FulfillmentStationRead:
        store = self._ensure_store()
        station = self.db.scalar(
            select(PedeOnFulfillmentStation).where(
                PedeOnFulfillmentStation.id == station_id,
                PedeOnFulfillmentStation.store_id == store.id,
            )
        )
        if station is None:
            raise LookupError("Estação não encontrada.")
        duplicate = self._station_by_code(store.id, payload.code)
        if duplicate is not None and duplicate.id != station.id:
            raise ValueError("Já existe uma estação com este código.")
        self._apply_station(station, payload)
        self._enqueue("station", station.id, "pedeon.station.updated")
        self.db.commit()
        self.db.refresh(station)
        return FulfillmentStationRead.model_validate(station)

    def _station_by_code(
        self, store_id: int, code: str
    ) -> PedeOnFulfillmentStation | None:
        return self.db.scalar(
            select(PedeOnFulfillmentStation).where(
                PedeOnFulfillmentStation.store_id == store_id,
                PedeOnFulfillmentStation.code == code,
            )
        )

    @staticmethod
    def _apply_station(
        station: PedeOnFulfillmentStation, payload: FulfillmentStationInput
    ) -> None:
        station.code = payload.code
        station.name = payload.name.strip()
        station.station_type = payload.station_type
        station.sort_order = payload.sort_order
        station.active = payload.active

    def _ensure_store(self) -> PedeOnStore:
        store = self.db.scalar(select(PedeOnStore).order_by(PedeOnStore.id).limit(1))
        if store is not None:
            return store
        store = PedeOnStore(
            public_slug=f"minha-loja-{uuid4().hex[:8]}",
            display_name="Minha loja",
            fulfillment_options=["pickup"],
            minimum_order_amount=Decimal("0"),
        )
        self.db.add(store)
        self.db.flush()
        return store

    def _payment_config(self, store_id: int, method: str) -> PedeOnPaymentConfiguration:
        config = self.db.scalar(
            select(PedeOnPaymentConfiguration).where(
                PedeOnPaymentConfiguration.store_id == store_id,
                PedeOnPaymentConfiguration.method == method,
            )
        )
        if config is None:
            config = PedeOnPaymentConfiguration(store_id=store_id, method=method)
            self.db.add(config)
            self.db.flush()
        return config

    def _settings_read(self, store: PedeOnStore) -> PedeOnSettingsRead:
        configs = {
            item.method: item
            for item in self.db.scalars(
                select(PedeOnPaymentConfiguration).where(
                    PedeOnPaymentConfiguration.store_id == store.id
                )
            )
        }
        manual = configs.get("manual_pix")
        manual_public = manual.public_configuration if manual else {}
        infinitepay = configs.get("infinitepay_pix")
        infinite_public = infinitepay.public_configuration if infinitepay else {}
        credit = configs.get("credit_card_on_delivery")
        debit = configs.get("debit_card_on_delivery")
        pickup = configs.get("pay_at_pickup")
        devices = self.db.scalars(
            select(PedeOnEdgeNode)
            .where(PedeOnEdgeNode.store_id == store.id)
            .order_by(PedeOnEdgeNode.device_label, PedeOnEdgeNode.id)
        ).all()
        terminal_capabilities = {item.value for item in TerminalCapability}
        return PedeOnSettingsRead(
            store=StoreSettingsRead.model_validate(
                {
                    **{
                        field: getattr(store, field)
                        for field in StoreSettingsUpdate.model_fields
                        if field not in {"inventory_policy", "accent_color", "dark_mode"}
                    },
                    "id": store.id,
                    "inventory_policy": (store.settings or {}).get(
                        "inventory_policy",
                        "warn_allow"
                        if store.experience_mode == "food_service"
                        else "strict_block",
                    ),
                    "accent_color": (store.settings or {}).get("accent_color", "#075E6F"),
                    "dark_mode": (store.settings or {}).get("dark_mode", False),
                }
            ),
            payments=PaymentSettingsRead(
                manual_pix=ManualPixUpdate(
                    enabled=manual.enabled if manual else False,
                    pickup_enabled=manual_public.get("pickup_enabled", True),
                    delivery_enabled=manual_public.get("delivery_enabled", True),
                    key_type=manual_public.get("key_type", "random"),
                    pix_key=manual_public.get("pix_key", ""),
                    recipient_name=manual_public.get("recipient_name", ""),
                    instructions=manual_public.get("instructions") or None,
                ),
                infinitepay=InfinitePayUpdate(
                    enabled=infinitepay.enabled if infinitepay else False,
                    pickup_enabled=infinite_public.get("pickup_enabled", True),
                    delivery_enabled=infinite_public.get("delivery_enabled", True),
                    handle=infinite_public.get("handle", ""),
                    auto_accept_after_confirmation=(
                        infinitepay.auto_accept_after_confirmation if infinitepay else True
                    ),
                ),
                delivery_card=DeliveryCardUpdate(
                    cash_enabled="cash" in ((pickup.public_configuration or {}).get("delivery_methods", []) if pickup else []),
                    pix_enabled="pix" in ((pickup.public_configuration or {}).get("delivery_methods", []) if pickup else []),
                    credit_enabled=credit.enabled if credit else False,
                    debit_enabled=debit.enabled if debit else False,
                ),
                pickup_payment=PickupPaymentUpdate(
                    enabled=pickup.enabled if pickup else False,
                    accepted_methods=(pickup.public_configuration or {}).get(
                        "accepted_methods",
                        ["cash", "pix", "credit_card", "debit_card"],
                    ) if pickup else ["cash", "pix", "credit_card", "debit_card"],
                ),
            ),
            terminals=[
                TerminalPermissionRead(
                    terminal_id=device.id,
                    cash_register_number=f"PedeOn {device.id}",
                    device_label=device.device_label or "Máquina sem nome",
                    app_version=device.app_version,
                    terminal_active=device.active,
                    enabled=device.active,
                    # Edge nodes also store infrastructure capabilities (for
                    # example catalog_cache and order_relay). Those values
                    # are not terminal permissions and cannot be serialized
                    # as TerminalCapability by the settings response.
                    capabilities=[
                        capability
                        for capability in (device.capabilities or [])
                        if capability in terminal_capabilities
                    ],
                    notification_mode="badge",
                    priority=device.sort_order,
                    device_role=device.device_role,
                    last_seen_at=device.last_seen_at,
                    status=device.status,
                )
                for device in devices
            ],
            delivery_zones=PedeOnDeliveryService(self.db).list(store.id),
            fulfillment_stations=[
                FulfillmentStationRead.model_validate(item)
                for item in self.db.scalars(
                    select(PedeOnFulfillmentStation)
                    .where(PedeOnFulfillmentStation.store_id == store.id)
                    .order_by(
                        PedeOnFulfillmentStation.sort_order,
                        PedeOnFulfillmentStation.name,
                    )
                )
            ],
            delivery_operation=DeliveryOperationUpdate.model_validate(
                (store.settings or {}).get("delivery_operation", {})
            ),
        )

    def _enqueue(self, aggregate_type: str, aggregate_id: int, event_type: str) -> None:
        self.db.add(
            PedeOnOutboxEvent(
                event_key=str(uuid4()),
                aggregate_type=aggregate_type,
                aggregate_id=str(aggregate_id),
                event_type=event_type,
                payload={"source": "erp_settings"},
            )
        )

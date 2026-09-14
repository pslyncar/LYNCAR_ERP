from __future__ import annotations

import unicodedata
from functools import lru_cache
from math import asin, cos, radians, sin, sqrt
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
import requests

from app.modules.pedeon.application.schemas import DeliveryZoneInput, DeliveryZoneRead
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnDeliveryZone,
    PedeOnStore,
)


MONEY = Decimal("0.01")


@dataclass(frozen=True)
class DeliveryQuote:
    zone_id: int | None
    zone_name: str | None
    fee: Decimal
    estimated_minutes_min: int | None
    estimated_minutes_max: int | None


def _normalized(value: str | None) -> str:
    text = unicodedata.normalize("NFKD", (value or "").strip().casefold())
    return " ".join("".join(c for c in text if not unicodedata.combining(c)).split())


@lru_cache(maxsize=4096)
def _postal_coordinates(postal_code: str) -> tuple[float, float] | None:
    try:
        response = requests.get(
            f"https://brasilapi.com.br/api/cep/v2/{postal_code}", timeout=4
        )
        response.raise_for_status()
        coordinates = response.json().get("location", {}).get("coordinates", {})
        return float(coordinates["latitude"]), float(coordinates["longitude"])
    except (requests.RequestException, KeyError, TypeError, ValueError):
        return None


def _distance_km(
    latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float
) -> float:
    latitude_delta = radians(latitude_b - latitude_a)
    longitude_delta = radians(longitude_b - longitude_a)
    value = (
        sin(latitude_delta / 2) ** 2
        + cos(radians(latitude_a))
        * cos(radians(latitude_b))
        * sin(longitude_delta / 2) ** 2
    )
    return 6371.0088 * 2 * asin(sqrt(value))


class PedeOnDeliveryService:
    def __init__(self, db: Session):
        self.db = db

    def list(self, store_id: int) -> list[DeliveryZoneRead]:
        return [
            DeliveryZoneRead.model_validate(zone)
            for zone in self.db.scalars(
                select(PedeOnDeliveryZone)
                .where(PedeOnDeliveryZone.store_id == store_id)
                .order_by(PedeOnDeliveryZone.sort_order, PedeOnDeliveryZone.id)
            ).all()
        ]

    def create(self, store_id: int, payload: DeliveryZoneInput) -> DeliveryZoneRead:
        zone = PedeOnDeliveryZone(store_id=store_id, **payload.model_dump())
        self.db.add(zone)
        self._commit_zone()
        self.db.refresh(zone)
        return DeliveryZoneRead.model_validate(zone)

    def update(
        self, store_id: int, zone_id: int, payload: DeliveryZoneInput
    ) -> DeliveryZoneRead:
        zone = self.db.scalar(
            select(PedeOnDeliveryZone).where(
                PedeOnDeliveryZone.id == zone_id,
                PedeOnDeliveryZone.store_id == store_id,
            )
        )
        if zone is None:
            raise LookupError("Área de entrega não encontrada.")
        for field, value in payload.model_dump().items():
            setattr(zone, field, value)
        zone.updated_at = datetime.now(timezone.utc)
        self._commit_zone()
        self.db.refresh(zone)
        return DeliveryZoneRead.model_validate(zone)

    def delete(self, store_id: int, zone_id: int) -> None:
        zone = self.db.scalar(
            select(PedeOnDeliveryZone).where(
                PedeOnDeliveryZone.id == zone_id,
                PedeOnDeliveryZone.store_id == store_id,
            )
        )
        if zone is None:
            raise LookupError("Área de entrega não encontrada.")
        self.db.delete(zone)
        self.db.commit()

    def _commit_zone(self) -> None:
        try:
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            raise ValueError(
                "Já existe uma área de entrega com este nome."
            ) from exc

    def quote(
        self,
        store: PedeOnStore,
        address: object,
        subtotal: Decimal,
    ) -> DeliveryQuote:
        operation = (store.settings or {}).get("delivery_operation", {})
        if operation.get("pricing_mode") == "fixed":
            minimum = Decimal(str(operation.get("fixed_minimum_order_amount", 0)))
            if subtotal < minimum:
                raise ValueError(
                    f"Pedido mínimo para entrega: R$ {minimum.quantize(MONEY):.2f}."
                )
            fee = Decimal(str(operation.get("fixed_fee_amount", 0)))
            free_above = operation.get("fixed_free_delivery_threshold")
            if free_above is not None and subtotal >= Decimal(str(free_above)):
                fee = Decimal("0")
            return DeliveryQuote(
                None,
                "Taxa fixa",
                fee.quantize(MONEY, rounding=ROUND_HALF_UP),
                int(operation.get("preparation_minutes_min", 20)),
                int(operation.get("preparation_minutes_max", 35)),
            )
        zones = self.db.scalars(
            select(PedeOnDeliveryZone)
            .where(
                PedeOnDeliveryZone.store_id == store.id,
                PedeOnDeliveryZone.active.is_(True),
            )
            .order_by(PedeOnDeliveryZone.sort_order, PedeOnDeliveryZone.id)
        ).all()
        if not zones:
            # Compatibilidade para lojas que já aceitavam entrega antes da
            # implantação das áreas configuráveis.
            return DeliveryQuote(None, None, Decimal("0.00"), None, None)

        postal_code = "".join(
            char for char in str(getattr(address, "postal_code", "")) if char.isdigit()
        )
        neighborhood = _normalized(str(getattr(address, "neighborhood", "")))
        city = _normalized(str(getattr(address, "city", "")))
        state = str(getattr(address, "state", "")).strip().upper()
        address_coordinates: tuple[float, float] | None = None

        matches: list[tuple[int, int, PedeOnDeliveryZone]] = []
        for zone in zones:
            if zone.city and _normalized(zone.city) != city:
                continue
            if zone.state and zone.state.strip().upper() != state:
                continue
            specificity = 0
            if zone.match_type == "postal_code_prefix":
                prefix = "".join(char for char in (zone.postal_code_prefix or "") if char.isdigit())
                if not prefix or not postal_code.startswith(prefix):
                    continue
                specificity = len(prefix) + 100
            elif zone.match_type == "neighborhood":
                if _normalized(zone.neighborhood) != neighborhood:
                    continue
                specificity = 50
            elif zone.match_type == "radius":
                if not postal_code:
                    continue
                address_coordinates = address_coordinates or _postal_coordinates(postal_code)
                if address_coordinates is None:
                    continue
                if (
                    zone.center_latitude is None
                    or zone.center_longitude is None
                    or zone.radius_km is None
                ):
                    continue
                distance = _distance_km(
                    float(zone.center_latitude),
                    float(zone.center_longitude),
                    address_coordinates[0],
                    address_coordinates[1],
                )
                if distance > float(zone.radius_km):
                    continue
                specificity = max(1, 40 - int(distance))
            else:
                continue
            matches.append((specificity, -zone.sort_order, zone))
        if not matches:
            raise ValueError("Ainda não entregamos neste endereço.")
        zone = max(matches, key=lambda item: (item[0], item[1]))[2]
        if subtotal < Decimal(zone.minimum_order_amount):
            raise ValueError(
                f"Pedido mínimo para {zone.name}: R$ "
                f"{Decimal(zone.minimum_order_amount).quantize(MONEY):.2f}."
            )
        fee = Decimal(zone.fee_amount)
        if (
            zone.free_delivery_threshold is not None
            and subtotal >= Decimal(zone.free_delivery_threshold)
        ):
            fee = Decimal("0")
        preparation_min = int(operation.get("preparation_minutes_min", 20))
        preparation_max = int(operation.get("preparation_minutes_max", 35))
        travel_min = zone.estimated_minutes_min or 0
        travel_max = zone.estimated_minutes_max or travel_min
        return DeliveryQuote(
            zone.id,
            zone.name,
            fee.quantize(MONEY, rounding=ROUND_HALF_UP),
            preparation_min + travel_min,
            preparation_max + travel_max,
        )

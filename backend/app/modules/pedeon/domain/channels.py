"""Canais que alimentam o nucleo unico de pedidos do PedeOn."""

from __future__ import annotations

import re
from enum import StrEnum


class OrderSource(StrEnum):
    PEDEON = "pedeon"
    ONSITE_WAITER = "onsite_waiter"
    ONSITE_QR = "onsite_qr"
    PDV_COUNTER = "pdv_counter"
    IFOOD = "ifood"
    FOOD99 = "food99"


_SOURCE_PATTERN = re.compile(r"^[a-z][a-z0-9_]{1,39}$")


def normalize_source_channel(value: str | OrderSource) -> str:
    """Normaliza canais conhecidos e permite adaptadores futuros seguros."""

    normalized = str(value).strip().lower().replace("-", "_")
    if not _SOURCE_PATTERN.fullmatch(normalized):
        raise ValueError("Canal de origem inválido.")
    return normalized

from __future__ import annotations

import json
from datetime import date
from decimal import Decimal
from urllib.request import urlopen

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.master_economic_index import MasterEconomicIndex

IBGE_IPCA_URL = "https://apisidra.ibge.gov.br/values/t/1737/n1/1/v/2266/p/last"


def sync_latest_ipca(db: Session) -> MasterEconomicIndex | None:
    """Fetch and persist the latest monthly IPCA from IBGE, idempotently."""
    try:
        with urlopen(IBGE_IPCA_URL, timeout=8) as response:
            payload = json.load(response)
        row = next((item for item in payload[1:] if item.get("V") not in (None, "-")), None)
        if row is None:
            return None
        month = str(row.get("D3C", ""))[:7]
        if len(month) != 7:
            month = date.today().strftime("%Y-%m")
        value = Decimal(str(row["V"]).replace(",", "."))
    except Exception:
        return None
    existing = db.scalar(select(MasterEconomicIndex).where(
        MasterEconomicIndex.index_name == "IPCA",
        MasterEconomicIndex.reference_month == month,
    ))
    if existing is None:
        existing = MasterEconomicIndex(index_name="IPCA", reference_month=month, percentage=value)
        db.add(existing)
    else:
        existing.percentage = value
    return existing


def accumulated_ipca(db: Session, start_month: str, end_month: str) -> Decimal:
    """Return compounded IPCA between YYYY-MM competencies (inclusive)."""
    rows = db.scalars(select(MasterEconomicIndex).where(
        MasterEconomicIndex.index_name == "IPCA",
        MasterEconomicIndex.reference_month > start_month,
        MasterEconomicIndex.reference_month <= end_month,
    ).order_by(MasterEconomicIndex.reference_month)).all()
    factor = Decimal("1")
    for row in rows:
        factor *= Decimal("1") + Decimal(str(row.percentage or 0)) / Decimal("100")
    return factor - Decimal("1")

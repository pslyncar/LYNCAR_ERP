from __future__ import annotations

from datetime import date

from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.core.config import get_settings
from app.models.client import Client
from app.services.master_holidays import ensure_master_holidays_for_scope


def ensure_holidays_for_period(
    db: Session,
    client: Client | None,
    period_start: date,
    period_end: date,
) -> None:
    settings = get_settings()
    if not settings.holiday_sync_enabled:
        return
    for year in range(period_start.year, period_end.year + 1):
        city = client.city.strip() if client and client.city else None
        city_code = getattr(client, "city_code", None)
        state = client.state.strip().upper() if client and client.state else None
        with MasterSessionLocal() as master_db:
            # Pre-aquece somente o cache central do Master.
            # Nao grava mais feriados no banco local do cliente.
            _ = db
            ensure_master_holidays_for_scope(
                master_db,
                year=year,
                city=city,
                city_code=city_code,
                state=state,
            )
            master_db.commit()


def _resolve_ibge_city_code(city: str, state: str) -> int | None:
    with MasterSessionLocal() as master_db:
        ensure_master_holidays_for_scope(
            master_db,
            year=date.today().year,
            city=city,
            city_code=None,
            state=state,
        )
        master_db.commit()
        from app.models.master_holiday import MasterHoliday
        from sqlalchemy import select

        holiday = master_db.scalar(
            select(MasterHoliday)
            .where(
                MasterHoliday.city == city.strip(),
                MasterHoliday.state == state.strip().upper(),
                MasterHoliday.city_code.is_not(None),
            )
            .limit(1)
        )
        if holiday and holiday.city_code:
            try:
                return int(holiday.city_code)
            except ValueError:
                return None
    return None

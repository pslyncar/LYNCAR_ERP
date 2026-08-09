from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.company import Company


BUSINESS_TIMEZONE = ZoneInfo("America/Sao_Paulo")
DEFAULT_CUTOFF_MINUTES = 180


def normalize_cutoff_minutes(value: int | None) -> int:
    if value is None:
        return DEFAULT_CUTOFF_MINUTES
    return max(0, min(1439, int(value)))


def business_date(value: datetime, cutoff_minutes: int) -> date:
    if value.tzinfo is None:
        localized = value.replace(tzinfo=timezone.utc).astimezone(BUSINESS_TIMEZONE)
    else:
        localized = value.astimezone(BUSINESS_TIMEZONE)
    return (localized - timedelta(minutes=normalize_cutoff_minutes(cutoff_minutes))).date()


def crossed_business_day(
    opened_at: datetime | None,
    reference_at: datetime | None,
    cutoff_minutes: int,
) -> bool:
    if opened_at is None or reference_at is None:
        return False
    return business_date(reference_at, cutoff_minutes) > business_date(
        opened_at, cutoff_minutes
    )


def company_cutoff_minutes(company_code: str) -> int:
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return DEFAULT_CUTOFF_MINUTES
        return normalize_cutoff_minutes(company.business_day_cutoff_minutes)

from __future__ import annotations

from calendar import monthrange
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.company_billing import CompanyBilling
from app.models.master_finance_setting import MasterFinanceSetting
from app.services.master_holidays import next_business_day
from app.services.economic_indexes import accumulated_ipca, sync_latest_ipca

BILLING_NOTICE_DAYS = 10
AUTO_BILLING_NOTE = "Cobrança mensal gerada automaticamente pelo sistema."
LEGACY_AUTO_BILLING_NOTES = {
    AUTO_BILLING_NOTE,
    "CobranÃ§a mensal gerada automaticamente pelo sistema.",
}


def billing_amount(company: Company) -> Decimal:
    text = (company.monthly_price or "0").strip().replace(".", "").replace(",", ".")
    try:
        value = Decimal(text)
    except Exception:
        value = Decimal("0")
    return value if value > 0 else Decimal("0")


def billing_day(company: Company, fallback: int) -> int:
    try:
        day = int(company.billing_day or fallback)
    except (TypeError, ValueError):
        day = fallback
    return min(max(day, 1), 31)


def has_billing_day(company: Company) -> bool:
    try:
        day = int(company.billing_day or "")
    except (TypeError, ValueError):
        return False
    return 1 <= day <= 31


def add_month(year: int, month: int) -> tuple[int, int]:
    if month == 12:
        return year + 1, 1
    return year, month + 1


def due_date_for(
    company: Company,
    year: int,
    month: int,
    fallback_day: int,
    *,
    db: Session | None = None,
) -> date:
    last_day = monthrange(year, month)[1]
    raw_due_date = date(year, month, min(billing_day(company, fallback_day), last_day))
    if db is None:
        return raw_due_date
    return next_business_day(
        db,
        raw_due_date,
        city=company.city,
        city_code=company.city_code,
        state=company.state,
    )


def reference_for(due_date: date) -> str:
    return due_date.strftime("%Y-%m")


def is_company_creation_month(company: Company, due_date: date) -> bool:
    created_at = company.created_at
    if created_at is None:
        return False
    return created_at.year == due_date.year and created_at.month == due_date.month


def company_can_be_billed(company: Company) -> bool:
    return bool(
        company.active
        and company.status == "active"
        and has_billing_day(company)
        and billing_amount(company) > 0
    )


def is_automatic_billing(row: CompanyBilling) -> bool:
    return row.notes in LEGACY_AUTO_BILLING_NOTES


def apply_overdue_charges_for_company_in_session(
    db: Session, company: Company, *, today: date | None = None
) -> list[CompanyBilling]:
    """Atualiza encargos de cobranças pendentes de forma idempotente.

    A multa é aplicada uma vez e os juros são simples, proporcionais aos dias
    em atraso após a carência. O principal nunca é alterado.
    """
    current = today or date.today()
    rows = list(db.scalars(select(CompanyBilling).where(
        CompanyBilling.company_id == company.id,
        CompanyBilling.status == "pending",
        CompanyBilling.due_date < current,
    )).all())
    changed: list[CompanyBilling] = []
    policy = db.scalar(select(MasterFinanceSetting).where(MasterFinanceSetting.id == 1))
    # Global Master policy is the default; company-specific legacy settings remain
    # available until an explicit per-company override is introduced.
    enabled = bool(policy.late_charges_enabled) if policy is not None else bool(company.late_charges_enabled)
    fee_percent = policy.late_fee_percent if policy is not None else company.late_fee_percent
    daily_percent = policy.late_interest_daily_percent if policy is not None else company.late_interest_daily_percent
    grace_days = policy.late_grace_days if policy is not None else company.late_grace_days
    monetary_enabled = bool(policy.monetary_correction_enabled) if policy is not None else False
    for row in rows:
        overdue_days = max((current - row.due_date).days - max(grace_days or 0, 0), 0)
        principal = Decimal(str(row.amount or 0))
        fee = (principal * Decimal(str(fee_percent or 0)) / Decimal("100")) if enabled and overdue_days > 0 else Decimal("0")
        interest = (principal * Decimal(str(daily_percent or 0)) * Decimal(overdue_days) / Decimal("100")) if enabled else Decimal("0")
        if monetary_enabled:
            sync_latest_ipca(db)
            ipca_factor = accumulated_ipca(db, row.due_date.strftime("%Y-%m"), current.strftime("%Y-%m"))
            correction = (principal * ipca_factor).quantize(Decimal("0.01"))
        else:
            correction = Decimal("0")
        if not hasattr(row, "monetary_correction_amount"):
            # Kept defensive for databases running before the migration.
            correction = Decimal("0")
        fee = fee.quantize(Decimal("0.01"))
        interest = interest.quantize(Decimal("0.01"))
        if Decimal(str(row.late_fee_amount or 0)) != fee or Decimal(str(row.interest_amount or 0)) != interest or Decimal(str(getattr(row, "monetary_correction_amount", 0) or 0)) != correction:
            row.late_fee_amount = fee
            row.interest_amount = interest
            if hasattr(row, "monetary_correction_amount"):
                row.monetary_correction_amount = correction
            row.mercado_pago_payment_id = None
            row.mercado_pago_status = None
            row.mercado_pago_external_reference = None
            row.mercado_pago_idempotency_key = None
            row.pix_qr_code = None
            row.pix_qr_code_base64 = None
            row.pix_ticket_url = None
            changed.append(row)
    return changed


def ensure_due_billings_for_company_in_session(
    db: Session,
    company: Company,
    *,
    today: date | None = None,
) -> list[CompanyBilling]:
    current_day = today or date.today()
    if not company_can_be_billed(company):
        return []

    current_due = due_date_for(
        company,
        current_day.year,
        current_day.month,
        current_day.day,
        db=db,
    )
    next_year, next_month = add_month(current_day.year, current_day.month)
    next_due = due_date_for(company, next_year, next_month, current_day.day, db=db)
    allowed_dates = {
        due_date
        for due_date in (current_due, next_due)
        if current_day >= due_date - timedelta(days=BILLING_NOTICE_DAYS)
    }
    created: list[CompanyBilling] = []

    for due_date in (current_due, next_due):
        if due_date not in allowed_dates:
            continue
        if is_company_creation_month(company, due_date):
            continue
        reference = reference_for(due_date)
        existing = db.scalar(
            select(CompanyBilling).where(
                CompanyBilling.company_id == company.id,
                CompanyBilling.reference_month == reference,
                CompanyBilling.status != "canceled",
            )
        )
        if existing is not None:
            if is_automatic_billing(existing) and existing.status == "pending":
                existing.due_date = due_date
                existing.amount = billing_amount(company)
                existing.payment_method = company.payment_method
                existing.notes = AUTO_BILLING_NOTE
            continue
        billing = CompanyBilling(
            company_id=company.id,
            reference_month=reference,
            due_date=due_date,
            amount=billing_amount(company),
            payment_method=company.payment_method,
            status="pending",
            notes=AUTO_BILLING_NOTE,
        )
        db.add(billing)
        created.append(billing)
    return created


def ensure_due_billings_for_company(
    company_code: str,
    *,
    today: date | None = None,
) -> list[CompanyBilling]:
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return []
        apply_overdue_charges_for_company_in_session(db, company, today=today)
        created = ensure_due_billings_for_company_in_session(db, company, today=today)
        db.commit()
        for billing in created:
            db.refresh(billing)
            _ = billing.company
        return created


def ensure_due_billings_for_all_companies(
    *,
    today: date | None = None,
) -> list[CompanyBilling]:
    with MasterSessionLocal() as db:
        companies = list(db.scalars(select(Company).where(Company.active.is_(True))).all())
        created: list[CompanyBilling] = []
        for company in companies:
            apply_overdue_charges_for_company_in_session(db, company, today=today)
            created.extend(
                ensure_due_billings_for_company_in_session(db, company, today=today)
            )
        db.commit()
        for billing in created:
            db.refresh(billing)
            _ = billing.company
        return created


def pending_billing_for_dashboard(company_code: str) -> CompanyBilling | None:
    today = date.today()
    ensure_due_billings_for_company(company_code, today=today)
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return None
        return db.scalar(
            select(CompanyBilling)
            .where(
                CompanyBilling.company_id == company.id,
                CompanyBilling.status == "pending",
                CompanyBilling.due_date <= today + timedelta(days=BILLING_NOTICE_DAYS),
            )
            .order_by(CompanyBilling.due_date.asc())
            .limit(1)
        )

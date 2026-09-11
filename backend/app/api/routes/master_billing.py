from datetime import UTC, date, datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.company_billing import CompanyBilling
from app.schemas.company_billing import (
    CompanyBillingCreate,
    CompanyBillingPayment,
    CompanyBillingRead,
    CompanyBillingUpdate,
    CompanyBillingWaive,
)
from app.services.company_billing import (
    AUTO_BILLING_NOTE,
    apply_overdue_charges_for_company_in_session,
    ensure_due_billings_for_all_companies,
    is_automatic_billing,
)
from app.services.mercado_pago import (
    apply_payment_status,
    create_pix_for_billing,
    get_payment,
)

router = APIRouter()
MANUAL_OVERRIDE_NOTE = "Ajuste manual aplicado nesta mensalidade."


def _read(row: CompanyBilling) -> CompanyBillingRead:
    amount = row.paid_amount if row.status == "paid" and row.paid_amount is not None else row.amount
    interest = Decimal(str(row.interest_amount or 0))
    late_fee = Decimal(str(row.late_fee_amount or 0))
    correction = Decimal(str(getattr(row, "monetary_correction_amount", 0) or 0))
    waived = Decimal(str(row.waived_amount or 0))
    return CompanyBillingRead(
        id=row.id,
        company_id=row.company_id,
        company_code=row.company.code,
        company_name=row.company.name,
        reference_month=row.reference_month,
        due_date=row.due_date,
        amount=amount,
        interest_amount=interest,
        late_fee_amount=late_fee,
        monetary_correction_amount=correction,
        waived_amount=waived,
        total_due=amount + interest + late_fee + correction - waived,
        waived_at=row.waived_at,
        waived_by=row.waived_by,
        waiver_reason=row.waiver_reason,
        payment_method=row.payment_method,
        status=row.status,
        paid_at=row.paid_at,
        paid_amount=row.paid_amount,
        mercado_pago_payment_id=row.mercado_pago_payment_id,
        mercado_pago_status=row.mercado_pago_status,
        mercado_pago_payer_name=row.mercado_pago_payer_name,
        mercado_pago_payer_email=row.mercado_pago_payer_email,
        mercado_pago_payer_document=row.mercado_pago_payer_document,
        pix_qr_code=row.pix_qr_code,
        pix_qr_code_base64=row.pix_qr_code_base64,
        pix_ticket_url=row.pix_ticket_url,
        notes=row.notes,
        created_at=row.created_at,
    )


@router.get("/billings", response_model=list[CompanyBillingRead])
def list_billings(
    status_filter: str | None = Query(default=None, alias="status"),
    company_id: int | None = None,
    _: dict = Depends(require_master_permission("master:billing")),
) -> list[CompanyBillingRead]:
    ensure_due_billings_for_all_companies()
    with MasterSessionLocal() as db:
        query = select(CompanyBilling).join(Company).order_by(
            CompanyBilling.due_date.desc(),
            Company.name,
        )
        if status_filter:
            query = query.where(CompanyBilling.status == status_filter)
        if company_id:
            query = query.where(CompanyBilling.company_id == company_id)
        return [_read(row) for row in db.scalars(query).all()]


@router.post("/billings", response_model=CompanyBillingRead, status_code=status.HTTP_201_CREATED)
def create_billing(
    payload: CompanyBillingCreate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        company = db.get(Company, payload.company_id)
        if company is None:
            raise HTTPException(status_code=404, detail="Empresa nao encontrada.")
        existing = db.scalar(
            select(CompanyBilling).where(
                CompanyBilling.company_id == payload.company_id,
                CompanyBilling.reference_month == payload.reference_month,
                CompanyBilling.status != "canceled",
            )
        )
        if existing is not None:
            raise HTTPException(
                status_code=409,
                detail="Ja existe cobranca ativa para esta empresa neste mes.",
            )
        billing = CompanyBilling(
            company_id=payload.company_id,
            reference_month=payload.reference_month,
            due_date=payload.due_date,
            amount=payload.amount,
            payment_method=payload.payment_method or company.payment_method,
            status="pending",
            notes=payload.notes,
        )
        db.add(billing)
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/{billing_id}/pix", response_model=CompanyBillingRead)
def generate_billing_pix(
    billing_id: int,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        # Recalcula os encargos antes de gerar/reutilizar o Pix. Assim, a cada
        # novo dia de atraso, o valor e o QR refletem a política vigente.
        apply_overdue_charges_for_company_in_session(
            db,
            billing.company,
            today=date.today(),
        )
        create_pix_for_billing(db, billing)
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/{billing_id}/sync", response_model=CompanyBillingRead)
def sync_billing_payment(
    billing_id: int,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        apply_overdue_charges_for_company_in_session(
            db,
            billing.company,
            today=date.today(),
        )
        if not billing.mercado_pago_payment_id:
            raise HTTPException(
                status_code=400,
                detail="Esta cobranca ainda nao tem pagamento Mercado Pago.",
            )
        payment = get_payment(billing.mercado_pago_payment_id)
        apply_payment_status(db, payment)
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/generate-current", response_model=list[CompanyBillingRead])
def generate_current_billings(_: dict = Depends(require_master_permission("master:billing"))) -> list[CompanyBillingRead]:
    created = ensure_due_billings_for_all_companies()
    return [_read(row) for row in created]


@router.put("/billings/{billing_id}", response_model=CompanyBillingRead)
def update_billing(
    billing_id: int,
    payload: CompanyBillingUpdate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        if billing.status == "paid":
            raise HTTPException(status_code=400, detail="Cobranca paga nao pode ser editada.")
        data = payload.model_dump(exclude_unset=True)
        if data.get("status") not in (None, "pending", "canceled"):
            raise HTTPException(status_code=400, detail="Status invalido para edicao.")
        financial_change = any(
            field in data for field in ("amount", "due_date", "payment_method")
        )
        for field, value in data.items():
            setattr(billing, field, value)
        if financial_change and billing.status == "pending":
            if is_automatic_billing(billing):
                billing.notes = f"{AUTO_BILLING_NOTE}\n{MANUAL_OVERRIDE_NOTE}"
            elif MANUAL_OVERRIDE_NOTE not in (billing.notes or ""):
                billing.notes = (
                    f"{billing.notes}\n{MANUAL_OVERRIDE_NOTE}"
                    if billing.notes
                    else MANUAL_OVERRIDE_NOTE
                )
            billing.mercado_pago_payment_id = None
            billing.mercado_pago_status = None
            billing.mercado_pago_payer_name = None
            billing.mercado_pago_payer_email = None
            billing.mercado_pago_payer_document = None
            billing.mercado_pago_external_reference = None
            billing.mercado_pago_idempotency_key = None
            billing.pix_qr_code = None
            billing.pix_qr_code_base64 = None
            billing.pix_ticket_url = None
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/{billing_id}/waive-charges", response_model=CompanyBillingRead)
def waive_billing_charges(
    billing_id: int,
    payload: CompanyBillingWaive,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    """Perdoa encargos sem alterar o principal e invalida o QR pendente."""
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        if billing.status == "paid":
            raise HTTPException(status_code=400, detail="Cobranca paga nao possui encargos abertos.")
        charges = Decimal(str((billing.interest_amount or 0) + (billing.late_fee_amount or 0) + getattr(billing, "monetary_correction_amount", 0)))
        waiver = min(payload.amount or charges, charges)
        billing.waived_amount = Decimal(str(billing.waived_amount or 0)) + waiver
        billing.waived_at = datetime.now(UTC)
        billing.waived_by = "master"
        billing.waiver_reason = payload.reason
        billing.mercado_pago_payment_id = None
        billing.mercado_pago_status = None
        billing.mercado_pago_payer_name = None
        billing.mercado_pago_payer_email = None
        billing.mercado_pago_payer_document = None
        billing.mercado_pago_external_reference = None
        billing.mercado_pago_idempotency_key = None
        billing.pix_qr_code = None
        billing.pix_qr_code_base64 = None
        billing.pix_ticket_url = None
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/mercado-pago/webhook")
async def mercado_pago_webhook(request: Request) -> dict:
    payload = await request.json()
    payment_id = None
    data = payload.get("data")
    if isinstance(data, dict):
        payment_id = data.get("id")
    payment_id = payment_id or payload.get("id")
    if payment_id is None:
        payment_id = request.query_params.get("id") or request.query_params.get("data.id")
    if payment_id is None:
        return {"ok": True, "ignored": True}

    payment = get_payment(str(payment_id))
    with MasterSessionLocal() as db:
        billing = apply_payment_status(db, payment)
        db.commit()
        return {"ok": True, "billing_id": billing.id if billing else None}


@router.post("/billings/{billing_id}/pay", response_model=CompanyBillingRead)
def pay_billing(
    billing_id: int,
    payload: CompanyBillingPayment,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        billing.status = "paid"
        billing.paid_at = datetime.now(UTC)
        billing.paid_amount = payload.paid_amount or billing.amount
        if payload.notes:
            billing.notes = payload.notes
        db.commit()
        db.refresh(billing)
        return _read(billing)


@router.post("/billings/{billing_id}/cancel", response_model=CompanyBillingRead)
def cancel_billing(
    billing_id: int,
    _: dict = Depends(require_master_permission("master:billing")),
) -> CompanyBillingRead:
    with MasterSessionLocal() as db:
        billing = db.get(CompanyBilling, billing_id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobranca nao encontrada.")
        billing.status = "canceled"
        db.commit()
        db.refresh(billing)
        return _read(billing)

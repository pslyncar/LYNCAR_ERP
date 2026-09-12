from __future__ import annotations

import json
import urllib.error
import urllib.request
from datetime import UTC, datetime
from decimal import Decimal
from uuid import uuid4

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.company_billing import CompanyBilling
from app.models.payment_setting import PaymentSetting

API_BASE_URL = "https://api.mercadopago.com"
INVALID_PAYMENT_STATUSES = frozenset({"cancelled", "canceled", "rejected", "expired"})
MONEY_QUANTUM = Decimal("0.01")


def configured_setting() -> tuple[str | None, str | None, str | None, str]:
    settings = get_settings()
    with MasterSessionLocal() as db:
        row = db.scalar(
            select(PaymentSetting).where(PaymentSetting.provider == "mercado_pago")
        )
        if row and row.active:
            return row.public_key, row.access_token, row.webhook_url, row.environment
    return (
        settings.mercado_pago_public_key,
        settings.mercado_pago_access_token,
        settings.mercado_pago_webhook_url,
        "test",
    )


def access_token() -> str:
    _, configured_token, _, _ = configured_setting()
    token = (configured_token or "").strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Access Token do Mercado Pago nao configurado.",
        )
    return token


def _request(method: str, path: str, *, body: dict | None = None, idempotency_key: str | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token()}",
    }
    if idempotency_key:
        headers["X-Idempotency-Key"] = idempotency_key
    request = urllib.request.Request(
        f"{API_BASE_URL}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(
            status_code=(
                status.HTTP_404_NOT_FOUND
                if exc.code == 404
                else status.HTTP_502_BAD_GATEWAY
            ),
            detail=f"Mercado Pago retornou erro: {detail}",
        ) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Nao foi possivel conectar ao Mercado Pago: {exc.reason}",
        ) from exc


def billing_reference(billing: CompanyBilling) -> str:
    return f"company_billing:{billing.id}"


def payer_email(company: Company) -> str:
    email = (company.email or "").strip()
    return email or "teste@lyncar.com.br"


def _billing_total_due(billing: CompanyBilling) -> Decimal:
    return (
        Decimal(str(billing.amount))
        + Decimal(str(getattr(billing, "interest_amount", 0) or 0))
        + Decimal(str(getattr(billing, "late_fee_amount", 0) or 0))
        + Decimal(str(getattr(billing, "monetary_correction_amount", 0) or 0))
        - Decimal(str(getattr(billing, "waived_amount", 0) or 0))
    ).quantize(MONEY_QUANTUM)


def _append_billing_note(billing: CompanyBilling, note: str) -> None:
    billing.notes = f"{billing.notes}\n{note}" if billing.notes else note


def _clear_pix_payment_link(billing: CompanyBilling, reason: str) -> None:
    old_payment_id = billing.mercado_pago_payment_id
    if old_payment_id:
        _append_billing_note(
            billing,
            f"QR Mercado Pago descartado ({reason}). Pagamento {old_payment_id}.",
        )
    billing.mercado_pago_payment_id = None
    billing.mercado_pago_status = None
    billing.mercado_pago_external_reference = None
    billing.mercado_pago_idempotency_key = None
    billing.pix_qr_code = None
    billing.pix_qr_code_base64 = None
    billing.pix_ticket_url = None
    billing.mercado_pago_payer_name = None
    billing.mercado_pago_payer_email = None
    billing.mercado_pago_payer_document = None


def create_pix_for_billing(db: Session, billing: CompanyBilling) -> CompanyBilling:
    if billing.status == "paid":
        return billing

    total_due = _billing_total_due(billing)
    if billing.mercado_pago_payment_id:
        try:
            current_payment = get_payment(billing.mercado_pago_payment_id)
        except HTTPException as exc:
            if exc.status_code == status.HTTP_404_NOT_FOUND:
                _clear_pix_payment_link(billing, "pagamento não encontrado no Mercado Pago")
            else:
                raise
        else:
            remote_status = str(current_payment.get("status") or "").lower()
            remote_amount = Decimal(
                str(current_payment.get("transaction_amount") or "0")
            ).quantize(MONEY_QUANTUM)
            billing.mercado_pago_status = remote_status or billing.mercado_pago_status
            if remote_status == "approved":
                apply_payment_status(db, current_payment)
                return billing
            if remote_status in INVALID_PAYMENT_STATUSES:
                _clear_pix_payment_link(billing, f"status Mercado Pago: {remote_status}")
            elif remote_amount != total_due:
                _clear_pix_payment_link(
                    billing,
                    f"valor atualizado de R$ {total_due} diferente do QR anterior",
                )
            elif billing.pix_qr_code:
                return billing
            else:
                _clear_pix_payment_link(billing, "QR ausente para pagamento pendente")
    elif any(
        value
        for value in (
            billing.pix_qr_code,
            billing.pix_qr_code_base64,
            billing.pix_ticket_url,
        )
    ):
        _clear_pix_payment_link(billing, "vínculo incompleto")

    company = billing.company
    idempotency_key = str(uuid4())
    _, _, configured_webhook_url, _ = configured_setting()
    webhook_url = (configured_webhook_url or "").strip() or None
    payload = {
        "transaction_amount": float(total_due),
        "description": f"Mensalidade Lyncar {billing.reference_month} - {company.name}",
        "payment_method_id": "pix",
        "external_reference": billing_reference(billing),
        "payer": {"email": payer_email(company)},
    }
    if webhook_url:
        payload["notification_url"] = webhook_url

    response = _request(
        "POST",
        "/v1/payments",
        body=payload,
        idempotency_key=idempotency_key,
    )
    transaction_data = (
        response.get("point_of_interaction", {})
        .get("transaction_data", {})
    )
    billing.mercado_pago_payment_id = str(response.get("id") or "")
    billing.mercado_pago_status = response.get("status")
    billing.mercado_pago_external_reference = response.get("external_reference") or billing_reference(billing)
    billing.mercado_pago_idempotency_key = idempotency_key
    billing.pix_qr_code = transaction_data.get("qr_code")
    billing.pix_qr_code_base64 = transaction_data.get("qr_code_base64")
    billing.pix_ticket_url = transaction_data.get("ticket_url")
    billing.payment_method = "pix"
    return billing


def get_payment(payment_id: str) -> dict:
    return _request("GET", f"/v1/payments/{payment_id}")


def _payer_data(payment: dict) -> tuple[str | None, str | None, str | None]:
    payer = payment.get("payer") or {}
    first_name = str(payer.get("first_name") or "").strip()
    last_name = str(payer.get("last_name") or "").strip()
    name = " ".join(part for part in (first_name, last_name) if part).strip()
    email = str(payer.get("email") or "").strip() or None
    identification = payer.get("identification") or {}
    document_type = str(identification.get("type") or "").strip()
    document_number = str(identification.get("number") or "").strip()
    document = " ".join(
        part for part in (document_type, document_number) if part
    ).strip() or None
    return name or None, email, document


def apply_payment_status(db: Session, payment: dict) -> CompanyBilling | None:
    external_reference = payment.get("external_reference")
    payment_id = str(payment.get("id") or "")
    billing = None
    if external_reference:
        billing = db.scalar(
            select(CompanyBilling).where(
                CompanyBilling.mercado_pago_external_reference == external_reference
            )
        )
        if billing is None and str(external_reference).startswith("company_billing:"):
            try:
                billing_id = int(str(external_reference).split(":", 1)[1])
            except ValueError:
                billing_id = None
            if billing_id is not None:
                billing = db.get(CompanyBilling, billing_id)
    if billing is None and payment_id:
        billing = db.scalar(
            select(CompanyBilling).where(
                CompanyBilling.mercado_pago_payment_id == payment_id
            )
        )
    if billing is None:
        return None

    # A regenerated QR creates a new payment. Ignore late webhooks from the
    # previous payment so an old approval cannot mark the new charge as paid.
    if (
        payment_id
        and billing.mercado_pago_payment_id
        and str(billing.mercado_pago_payment_id) != payment_id
    ):
        return billing

    billing.mercado_pago_payment_id = payment_id or billing.mercado_pago_payment_id
    billing.mercado_pago_status = payment.get("status")
    billing.mercado_pago_external_reference = external_reference or billing.mercado_pago_external_reference
    payer_name, payer_email, payer_document = _payer_data(payment)
    billing.mercado_pago_payer_name = payer_name or billing.mercado_pago_payer_name
    billing.mercado_pago_payer_email = payer_email or billing.mercado_pago_payer_email
    billing.mercado_pago_payer_document = payer_document or billing.mercado_pago_payer_document
    if payment.get("status") == "approved" and billing.status != "paid":
        billing.status = "paid"
        billing.paid_at = datetime.now(UTC)
        billing.paid_amount = Decimal(str(payment.get("transaction_amount") or billing.amount))
        billing.payment_method = "pix"
        note = f"Baixa automática Mercado Pago. Pagamento {payment_id}."
        billing.notes = f"{billing.notes}\n{note}" if billing.notes else note
    return billing

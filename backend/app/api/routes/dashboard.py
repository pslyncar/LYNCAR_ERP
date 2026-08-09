from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, require_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.company import Company
from app.models.company_billing import CompanyBilling
from app.models.client import Client
from app.models.dashboard_content import DashboardContent
from app.models.equipment import Equipment
from app.models.fiscal import CompanyFiscalSetting
from app.models.monitoring import Alert
from app.models.ticket import Ticket
from app.models.user import User
from app.schemas.dashboard import (
    DashboardAlertRead,
    DashboardContentRead,
    DashboardSummaryRead,
)
from app.schemas.company_billing import CompanyBillingRead
from app.services.company_billing import pending_billing_for_dashboard
from app.services.mercado_pago import create_pix_for_billing

router = APIRouter()

ONLINE_THRESHOLD_MINUTES = 5


def billing_read(row: CompanyBilling) -> CompanyBillingRead:
    return CompanyBillingRead(
        id=row.id,
        company_id=row.company_id,
        company_code=row.company.code,
        company_name=row.company.name,
        reference_month=row.reference_month,
        due_date=row.due_date,
        amount=row.amount,
        payment_method=row.payment_method,
        status=row.status,
        paid_at=row.paid_at,
        paid_amount=row.paid_amount,
        mercado_pago_payment_id=row.mercado_pago_payment_id,
        mercado_pago_status=row.mercado_pago_status,
        pix_qr_code=row.pix_qr_code,
        pix_qr_code_base64=row.pix_qr_code_base64,
        pix_ticket_url=row.pix_ticket_url,
        notes=row.notes,
        created_at=row.created_at,
    )


def count_scalar(db: Session, statement) -> int:
    return int(db.scalar(statement) or 0)


def build_monitoring_alerts(db: Session) -> list[DashboardAlertRead]:
    rows = db.execute(
        select(Alert, Equipment, Client)
        .join(Equipment, Equipment.id == Alert.equipment_id)
        .join(Client, Client.id == Equipment.client_id)
        .where(Alert.resolved.is_(False))
        .order_by(Alert.created_at.desc())
        .limit(100)
    ).all()

    return [
        DashboardAlertRead(
            equipment_id=equipment.id,
            hostname=equipment.hostname,
            client_id=client.id,
            client_name=client.name,
            type=alert.type,
            severity=alert.severity,
            message=alert.message,
        )
        for alert, equipment, client in rows
    ]


def get_company_context(company_code: str | None) -> tuple[str | None, list[str]]:
    if not company_code:
        return None, []
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return None, []
        return company.business_type, company.enabled_modules or []


def list_dashboard_contents(
    company_code: str | None,
    business_type: str | None,
    enabled_modules: list[str],
) -> list[DashboardContentRead]:
    with MasterSessionLocal() as master_db:
        query = (
            select(DashboardContent)
            .where(DashboardContent.active.is_(True))
            .order_by(DashboardContent.sort_order, DashboardContent.id.desc())
        )
        rows = list(master_db.scalars(query).all())
    filtered = [
        item
        for item in rows
        if not item.segment
        or item.segment == "todos"
        or item.segment == business_type
        or item.segment in enabled_modules
    ]
    contents = [
        DashboardContentRead(
            id=item.id,
            content_type=item.content_type,
            title=item.title,
            description=item.description,
            badge=item.badge,
            price_label=item.price_label,
            image_url=item.image_url,
            target_url=item.target_url,
            button_label=item.button_label,
            segment=item.segment,
            sort_order=item.sort_order,
        )
        for item in filtered
    ]
    if company_code:
        overdue = master_db_overdue_billing(company_code)
        if overdue is not None:
            contents.insert(
                0,
                DashboardContentRead(
                    id=-overdue.id,
                    content_type="billing_overdue",
                    title="Pagamento em atraso",
                    description=(
                        "Existe uma mensalidade vencida. Regularize o pagamento "
                        "para evitar bloqueio do sistema."
                    ),
                    badge="Atenção",
                    price_label=f"Vencimento: {overdue.due_date.strftime('%d/%m/%Y')}",
                    button_label="Falar com suporte",
                    sort_order=-1000,
                ),
            )
    return contents


def master_db_overdue_billing(company_code: str) -> CompanyBilling | None:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            return None
        return master_db.scalar(
            select(CompanyBilling)
            .where(
                CompanyBilling.company_id == company.id,
                CompanyBilling.status == "pending",
                CompanyBilling.due_date < date.today(),
            )
            .order_by(CompanyBilling.due_date.asc())
            .limit(1)
        )


def master_db_contract_notice(company_code: str) -> Company | None:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None or company.contract_expires_at is None:
            return None
        if (company.contract_expires_at - date.today()).days <= 30:
            return company
        return None


def has_fiscal_certificate(db: Session) -> bool:
    setting = db.scalar(select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc()))
    if setting is None:
        return False
    return bool(setting.certificate_encrypted_blob and setting.certificate_password_encrypted)


def list_dashboard_contents_with_billing(
    company_code: str | None,
    business_type: str | None,
    enabled_modules: list[str],
) -> list[DashboardContentRead]:
    contents = list_dashboard_contents(
        company_code=None,
        business_type=business_type,
        enabled_modules=enabled_modules,
    )
    if not company_code:
        return contents

    contract_company = master_db_contract_notice(company_code)
    if contract_company is not None and contract_company.contract_expires_at is not None:
        days = (contract_company.contract_expires_at - date.today()).days
        overdue = days < 0
        due_text = contract_company.contract_expires_at.strftime("%d/%m/%Y")
        contents.insert(
            0,
            DashboardContentRead(
                id=-900000 - contract_company.id,
                content_type="contract_overdue" if overdue else "contract_due",
                title="Contrato vencido" if overdue else "Renovação de contrato",
                description=(
                    "Seu contrato anual venceu. Entre em contato com a Lyncar "
                    "para regularizar a continuidade do sistema."
                    if overdue
                    else (
                        "Seu contrato anual está próximo do vencimento. "
                        "A Lyncar entrará em contato para confirmar a renovação."
                    )
                ),
                badge="Contrato" if not overdue else "Atenção",
                price_label=f"Vencimento: {due_text}",
                button_label="Falar com suporte",
                sort_order=-1100,
            ),
        )

    billing = pending_billing_for_dashboard(company_code)
    if billing is None:
        return contents

    overdue = billing.due_date < date.today()
    due_text = billing.due_date.strftime("%d/%m/%Y")
    contents.insert(
        0,
        DashboardContentRead(
            id=-billing.id,
            content_type="billing_overdue" if overdue else "billing_due",
            title="Pagamento em atraso" if overdue else "Mensalidade gerada",
            description=(
                "Existe uma mensalidade vencida. Regularize o pagamento "
                "para evitar bloqueio do sistema."
                if overdue
                else (
                    "Sua mensalidade do sistema foi gerada. Efetue o pagamento "
                    f"até {due_text}."
                )
            ),
            badge="Atenção" if overdue else "Vencimento",
            price_label=f"Vencimento: {due_text}",
            button_label="Falar com suporte" if overdue else "Ver pagamento",
            sort_order=-1000,
        ),
    )
    return contents


@router.post("/billing-payment", response_model=CompanyBillingRead)
def get_dashboard_billing_payment(
    current_user: User = Depends(require_permission("dashboard:view")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> CompanyBillingRead:
    company_code = None
    if credentials is not None:
        payload = decode_access_token(credentials.credentials)
        company_code = payload.get("company_code")
    if not isinstance(company_code, str) or not company_code:
        raise HTTPException(status_code=404, detail="Empresa não encontrada.")

    pending = pending_billing_for_dashboard(company_code)
    if pending is None:
        raise HTTPException(status_code=404, detail="Nenhuma cobrança em aberto.")

    with MasterSessionLocal() as master_db:
        billing = master_db.get(CompanyBilling, pending.id)
        if billing is None:
            raise HTTPException(status_code=404, detail="Cobrança não encontrada.")
        _ = billing.company
        create_pix_for_billing(master_db, billing)
        master_db.commit()
        master_db.refresh(billing)
        _ = billing.company
        return billing_read(billing)


@router.get("/summary", response_model=DashboardSummaryRead)
def get_dashboard_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("dashboard:view")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> DashboardSummaryRead:
    online_since = datetime.now(UTC) - timedelta(minutes=ONLINE_THRESHOLD_MINUTES)
    company_code = None
    if credentials is not None:
        payload = decode_access_token(credentials.credentials)
        company_code = payload.get("company_code")
    business_type, enabled_modules = get_company_context(
        company_code if isinstance(company_code, str) else None
    )
    is_technical_dashboard = (
        business_type == "assistencia_tecnica"
        or "monitoring" in enabled_modules
        or "equipments" in enabled_modules
    )

    total_clients = count_scalar(db, select(func.count(Client.id)))
    total_equipments = count_scalar(db, select(func.count(Equipment.id)))
    online_equipments = count_scalar(
        db,
        select(func.count(Equipment.id)).where(Equipment.last_seen_at >= online_since),
    )
    offline_equipments = max(total_equipments - online_equipments, 0)

    open_tickets = count_scalar(
        db,
        select(func.count(Ticket.id)).where(Ticket.status == "aberto"),
    )
    in_progress_tickets = count_scalar(
        db,
        select(func.count(Ticket.id)).where(Ticket.status == "em_andamento"),
    )
    completed_tickets = count_scalar(
        db,
        select(func.count(Ticket.id)).where(Ticket.status == "concluido"),
    )
    canceled_tickets = count_scalar(
        db,
        select(func.count(Ticket.id)).where(Ticket.status == "cancelado"),
    )

    return DashboardSummaryRead(
        dashboard_kind="technical" if is_technical_dashboard else "showcase",
        business_type=business_type,
        has_fiscal_certificate=has_fiscal_certificate(db),
        total_clients=total_clients,
        total_equipments=total_equipments,
        online_equipments=online_equipments,
        offline_equipments=offline_equipments,
        open_tickets=open_tickets,
        in_progress_tickets=in_progress_tickets,
        completed_tickets=completed_tickets,
        canceled_tickets=canceled_tickets,
        alerts=build_monitoring_alerts(db) if is_technical_dashboard else [],
        contents=list_dashboard_contents_with_billing(
            company_code if isinstance(company_code, str) else None,
            business_type,
            enabled_modules,
        ),
    )

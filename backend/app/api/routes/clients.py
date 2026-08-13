import calendar
from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.client import Client
from app.models.receivable import Receivable
from app.models.user import User
from app.schemas.client import ClientCreate, ClientRead, ClientUpdate

router = APIRouter()
MONTHLY_RECEIVABLE_NOTE_PREFIX = "Mensalidade gerada automaticamente pelo cadastro do cliente."


def _normalize_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    return normalized or None


def _only_digits(value: str | None) -> str | None:
    if value is None:
        return None
    digits = "".join(char for char in value if char.isdigit())
    return digits or None


def _client_duplicate_filter(client_in: ClientCreate | ClientUpdate, exclude_id: int | None = None):
    checks = []
    document = _only_digits(client_in.document_number)
    email = _normalize_text(str(client_in.email) if client_in.email else None)
    name = _normalize_text(client_in.name)
    phone = _only_digits(client_in.mobile_phone or client_in.phone)

    if document:
        checks.append(func.regexp_replace(Client.document_number, r"\D", "", "g") == document)
    if email:
        checks.append(func.lower(Client.email) == email)
    if name and phone:
        checks.append(
            func.lower(func.trim(Client.name)) == name,
        )
        checks[-1] = checks[-1] & (
            func.regexp_replace(func.coalesce(Client.mobile_phone, Client.phone, ""), r"\D", "", "g")
            == phone
        )
    elif name:
        checks.append(func.lower(func.trim(Client.name)) == name)
    if not checks:
        return None
    expression = or_(*checks)
    if exclude_id is not None:
        expression = expression & (Client.id != exclude_id)
    return expression


def ensure_unique_client(
    db: Session,
    client_in: ClientCreate | ClientUpdate,
    exclude_id: int | None = None,
) -> None:
    duplicate_filter = _client_duplicate_filter(client_in, exclude_id)
    if duplicate_filter is None:
        return
    duplicate = db.scalar(select(Client).where(duplicate_filter).limit(1))
    if duplicate is None:
        return
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="Cliente ja cadastrado. Verifique nome, documento, e-mail ou telefone.",
    )


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


def _monthly_due_date(year: int, month: int, due_day: int) -> datetime:
    last_day = calendar.monthrange(year, month)[1]
    return datetime(year, month, min(due_day, last_day))


def _monthly_period_bounds(reference: datetime) -> tuple[datetime, datetime]:
    start = datetime(reference.year, reference.month, 1)
    if reference.month == 12:
        end = datetime(reference.year + 1, 1, 1)
    else:
        end = datetime(reference.year, reference.month + 1, 1)
    return start, end


def ensure_monthly_contract_is_valid(client: Client) -> None:
    if client.contract_type != "mensal":
        return
    if client.monthly_fee <= Decimal("0"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Informe o valor mensal do contrato.",
        )
    if client.monthly_due_day is None or not 1 <= client.monthly_due_day <= 31:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Informe o dia de vencimento da mensalidade.",
        )


def sync_current_month_receivable(db: Session, client: Client) -> None:
    if client.contract_type != "mensal" or not client.active:
        return
    ensure_monthly_contract_is_valid(client)
    now = datetime.utcnow()
    period_start, period_end = _monthly_period_bounds(now)
    due_date = _monthly_due_date(now.year, now.month, client.monthly_due_day or 1)
    description = f"Mensalidade {client.name} - {now.month:02d}/{now.year}"
    marker = f"{MONTHLY_RECEIVABLE_NOTE_PREFIX} Competencia {now.year}-{now.month:02d}."

    receivable = db.scalar(
        select(Receivable).where(
            Receivable.client_id == client.id,
            Receivable.due_date >= period_start,
            Receivable.due_date < period_end,
            Receivable.notes.like(f"{MONTHLY_RECEIVABLE_NOTE_PREFIX}%"),
        )
    )
    if receivable is None:
        receivable = Receivable(
            client_id=client.id,
            description=description,
            original_amount=client.monthly_fee,
            paid_amount=Decimal("0"),
            balance_amount=client.monthly_fee,
            status="open",
            due_date=due_date,
            notes=marker,
        )
        db.add(receivable)
        db.flush()
        receivable.number = receivable_number(receivable.id)
        return

    if receivable.status == "paid":
        return
    receivable.description = description
    receivable.due_date = due_date
    receivable.original_amount = client.monthly_fee
    receivable.balance_amount = max(
        Decimal("0"),
        client.monthly_fee - receivable.paid_amount,
    )
    receivable.status = "open" if receivable.paid_amount <= 0 else "partial"
    receivable.notes = marker


@router.post("", response_model=ClientRead, status_code=status.HTTP_201_CREATED)
def create_client(
    client_in: ClientCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("clients:create")),
) -> Client:
    ensure_unique_client(db, client_in)
    client = Client(**client_in.model_dump())
    ensure_monthly_contract_is_valid(client)
    db.add(client)
    db.flush()
    sync_current_month_receivable(db, client)
    db.commit()
    db.refresh(client)
    return client


@router.get("", response_model=list[ClientRead])
def list_clients(
    q: str | None = Query(default=None, min_length=1),
    limit: int = Query(default=500, ge=1, le=1000),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "clients:view",
            "sales:view",
            "sales:manual",
            "sales:create",
            "service_orders:view",
            "service_orders:create",
            "tickets:view",
            "tickets:create",
        )
    ),
) -> list[Client]:
    query = select(Client).order_by(Client.name)
    if q is not None and q.strip():
        term = q.strip()
        like = f"%{term}%"
        digits = "".join(char for char in term if char.isdigit())
        filters = [
            Client.name.ilike(like),
            Client.trade_name.ilike(like),
            Client.contact_person.ilike(like),
            Client.email.ilike(like),
            Client.phone.ilike(like),
            Client.mobile_phone.ilike(like),
            Client.document_number.ilike(like),
        ]
        if digits:
            digit_like = f"%{digits}%"
            filters.extend(
                [
                    Client.document_number.ilike(digit_like),
                    Client.phone.ilike(digit_like),
                    Client.mobile_phone.ilike(digit_like),
                ]
            )
        query = query.where(or_(*filters))
    query = query.limit(limit)
    return list(db.scalars(query).all())


@router.get("/{client_id}", response_model=ClientRead)
def get_client(
    client_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "clients:view",
            "sales:view",
            "sales:manual",
            "sales:create",
            "service_orders:view",
            "service_orders:create",
            "tickets:view",
            "tickets:create",
        )
    ),
) -> Client:
    client = db.get(Client, client_id)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cliente nao encontrado.",
        )
    return client


@router.put("/{client_id}", response_model=ClientRead)
def update_client(
    client_id: int,
    client_in: ClientUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("clients:update")),
) -> Client:
    client = db.get(Client, client_id)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cliente nao encontrado.",
        )

    merged_data = ClientUpdate(**{
        **{
            "name": client.name,
            "person_type": client.person_type,
            "trade_name": client.trade_name,
            "document_number": client.document_number,
            "state_registration": client.state_registration,
            "municipal_registration": client.municipal_registration,
            "contact_person": client.contact_person,
            "phone": client.phone,
            "mobile_phone": client.mobile_phone,
            "email": client.email,
            "secondary_email": client.secondary_email,
            "address": client.address,
            "address_number": client.address_number,
            "address_complement": client.address_complement,
            "neighborhood": client.neighborhood,
            "city": client.city,
            "state": client.state,
            "zip_code": client.zip_code,
            "contract_type": client.contract_type,
            "monthly_fee": client.monthly_fee,
            "monthly_due_day": client.monthly_due_day,
            "allow_credit": client.allow_credit,
            "credit_limit": client.credit_limit,
            "credit_status": client.credit_status,
            "payment_terms": client.payment_terms,
            "billing_notes": client.billing_notes,
            "notes": client.notes,
            "active": client.active,
        },
        **client_in.model_dump(exclude_unset=True),
    })
    ensure_unique_client(db, merged_data, exclude_id=client_id)

    for field, value in client_in.model_dump(exclude_unset=True).items():
        setattr(client, field, value)

    ensure_monthly_contract_is_valid(client)
    sync_current_month_receivable(db, client)
    db.commit()
    db.refresh(client)
    return client


@router.delete("/{client_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_client(
    client_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("clients:delete")),
) -> None:
    client = db.get(Client, client_id)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cliente nao encontrado.",
        )

    db.delete(client)
    db.commit()

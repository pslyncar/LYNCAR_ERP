import socket
import unicodedata
from datetime import UTC, datetime
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import bearer_scheme, require_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.client import Client
from app.models.company import Company
from app.models.equipment import Equipment
from app.models.product import Product
from app.models.service_order import ServiceOrder, ServiceOrderItem
from app.models.ticket import Ticket
from app.models.user import User
from app.schemas.service_order import (
    ServiceOrderCreate,
    ServiceOrderItemCreate,
    ServiceOrderItemRead,
    ServiceOrderRead,
    ServiceOrderUpdate,
)
from app.schemas.printing import ThermalPrintRequest, ThermalPrintResponse
from app.services.access_control import user_has_configured_permission
from app.services.service_order_totals import recalculate_service_order_totals

router = APIRouter()

MONEY_QUANT = Decimal("0.01")
DEFAULT_MAX_DISCOUNT_PERCENT = Decimal("100.00")


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def percent(value: Decimal | int | float | str | None) -> Decimal:
    if value is None:
        return DEFAULT_MAX_DISCOUNT_PERCENT
    normalized = Decimal(str(value)).quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
    return max(Decimal("0.00"), min(DEFAULT_MAX_DISCOUNT_PERCENT, normalized))


def tenant_company_code(
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token ausente.")
    payload = decode_access_token(credentials.credentials)
    company_code = payload.get("company_code")
    if not isinstance(company_code, str) or not company_code.strip():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Empresa invalida.")
    return company_code.strip()


def sales_max_discount_percent(company_code: str) -> Decimal:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa nao encontrada.")
        return percent(company.sales_max_discount_percent)


def strip_accents(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return normalized.encode("ascii", "ignore").decode("ascii")


def receipt_line(label: str, value: object | None, width: int) -> list[str]:
    text = f"{label}: {value or '-'}"
    clean = strip_accents(text).replace("\r", " ").replace("\n", " ")
    if len(clean) <= width:
        return [clean]
    lines = []
    remaining = clean
    while remaining:
        lines.append(remaining[:width])
        remaining = remaining[width:]
    return lines


def build_service_order_receipt(service_order: ServiceOrder, width: int) -> bytes:
    client = service_order.client
    equipment_label = service_order.received_equipment
    if not equipment_label and service_order.equipment is not None:
        equipment_label = service_order.equipment.hostname
    code = service_order.number or service_order_code(service_order.id)
    opened = service_order.opened_at.strftime("%d/%m/%Y %H:%M")

    lines = [
        "PAPEZZOSYNC".center(width),
        "COMPROVANTE DE OS".center(width),
        "=" * width,
        *receipt_line("OS", code, width),
        *receipt_line("Abertura", opened, width),
        *receipt_line("Cliente", client.name if client else None, width),
        *receipt_line("Telefone", getattr(client, "phone", None), width),
        *receipt_line("Equipamento", equipment_label, width),
        "-" * width,
        "PROBLEMA INFORMADO",
        *receipt_line("", service_order.request_description, width),
        "-" * width,
        *receipt_line("Status", service_order.status, width),
        *receipt_line("Prioridade", service_order.priority, width),
    ]
    if service_order.waiting_reason:
        lines.extend(receipt_line("Aguardando", service_order.waiting_reason, width))
    lines.extend(
        [
            "-" * width,
            "Recebemos o equipamento acima para avaliacao.",
            "Nao coletamos senhas sem consentimento.",
            "",
            "Assinatura do cliente:",
            "",
            "_" * width,
            "",
            "",
        ]
    )

    text = "\n".join(strip_accents(line) for line in lines)
    return b"\x1b@" + text.encode("cp850", errors="replace") + b"\n\n\n\x1dV\x00"


def ensure_service_order_relations(
    db: Session,
    client_id: int | None,
    equipment_id: int | None,
    ticket_id: int | None,
    assigned_user_id: int | None,
) -> None:
    if client_id is not None and db.get(Client, client_id) is None:
        raise HTTPException(status_code=404, detail="Cliente nao encontrado.")

    if equipment_id is not None:
        equipment = db.get(Equipment, equipment_id)
        if equipment is None:
            raise HTTPException(status_code=404, detail="Equipamento nao encontrado.")
        if client_id is not None and equipment.client_id != client_id:
            raise HTTPException(
                status_code=400,
                detail="Equipamento nao pertence ao cliente informado.",
            )

    if ticket_id is not None:
        ticket = db.get(Ticket, ticket_id)
        if ticket is None:
            raise HTTPException(status_code=404, detail="Chamado nao encontrado.")
        if client_id is not None and ticket.client_id != client_id:
            raise HTTPException(
                status_code=400,
                detail="Chamado nao pertence ao cliente informado.",
            )

    if assigned_user_id is not None and db.get(User, assigned_user_id) is None:
        raise HTTPException(status_code=404, detail="Tecnico nao encontrado.")


def apply_service_order_closed_at(service_order: ServiceOrder, new_status: str | None) -> None:
    if new_status in {"concluida", "cancelada"} and service_order.closed_at is None:
        service_order.closed_at = datetime.now(UTC)
    if new_status not in {None, "concluida", "cancelada"}:
        service_order.closed_at = None


def apply_service_order_waiting_rule(service_order: ServiceOrder) -> None:
    if service_order.status == "aguardando_aprovacao":
        if not service_order.waiting_reason or len(service_order.waiting_reason.strip()) < 3:
            raise HTTPException(
                status_code=400,
                detail="Informe o motivo quando a OS estiver aguardando.",
            )
        service_order.waiting_reason = service_order.waiting_reason.strip()
    else:
        service_order.waiting_reason = None


def ensure_service_order_discount_allowed(
    db: Session,
    current_user: User,
    service_order: ServiceOrder,
    company_code: str,
) -> None:
    if service_order.discount_amount <= 0:
        return
    if user_has_configured_permission(db, current_user, "sales:discount:override"):
        return
    max_discount_percent = sales_max_discount_percent(company_code)
    max_discount = money(
        (service_order.items_amount + service_order.labor_amount)
        * max_discount_percent
        / Decimal("100")
    )
    if service_order.discount_amount > max_discount:
        raise HTTPException(
            status_code=400,
            detail=(
                "Desconto acima do limite permitido para OS. "
                f"Maximo permitido: {max_discount_percent}%."
            ),
        )


def service_order_code(service_order_id: int) -> str:
    return f"M{service_order_id}"


def get_service_order_or_404(db: Session, service_order_id: int) -> ServiceOrder:
    service_order = db.scalar(
        select(ServiceOrder)
        .options(
            selectinload(ServiceOrder.items),
            selectinload(ServiceOrder.client),
            selectinload(ServiceOrder.equipment),
        )
        .where(ServiceOrder.id == service_order_id)
    )
    if service_order is None:
        raise HTTPException(status_code=404, detail="Ordem de servico nao encontrada.")
    return service_order


@router.post("", response_model=ServiceOrderRead, status_code=status.HTTP_201_CREATED)
def create_service_order(
    service_order_in: ServiceOrderCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:create")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> ServiceOrder:
    ensure_service_order_relations(
        db,
        service_order_in.client_id,
        service_order_in.equipment_id,
        service_order_in.ticket_id,
        service_order_in.assigned_user_id,
    )
    service_order = ServiceOrder(**service_order_in.model_dump())
    apply_service_order_closed_at(service_order, service_order.status)
    apply_service_order_waiting_rule(service_order)
    recalculate_service_order_totals(service_order)
    ensure_service_order_discount_allowed(
        db,
        current_user,
        service_order,
        tenant_company_code(credentials),
    )
    db.add(service_order)
    db.commit()
    db.refresh(service_order)
    if not service_order.number:
        service_order.number = service_order_code(service_order.id)
        db.commit()
    return get_service_order_or_404(db, service_order.id)


@router.get("", response_model=list[ServiceOrderRead])
def list_service_orders(
    client_id: int | None = Query(default=None),
    status_filter: str | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:view")),
) -> list[ServiceOrder]:
    query = select(ServiceOrder).options(selectinload(ServiceOrder.items)).order_by(
        ServiceOrder.opened_at.desc()
    )
    if client_id is not None:
        query = query.where(ServiceOrder.client_id == client_id)
    if status_filter is not None:
        query = query.where(ServiceOrder.status == status_filter)
    return list(db.scalars(query).all())


@router.get("/{service_order_id}", response_model=ServiceOrderRead)
def get_service_order(
    service_order_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:view")),
) -> ServiceOrder:
    return get_service_order_or_404(db, service_order_id)


@router.put("/{service_order_id}", response_model=ServiceOrderRead)
def update_service_order(
    service_order_id: int,
    service_order_in: ServiceOrderUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:update")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> ServiceOrder:
    service_order = get_service_order_or_404(db, service_order_id)
    update_data = service_order_in.model_dump(exclude_unset=True)

    next_client_id = update_data.get("client_id", service_order.client_id)
    ensure_service_order_relations(
        db,
        next_client_id,
        update_data.get("equipment_id", service_order.equipment_id),
        update_data.get("ticket_id", service_order.ticket_id),
        update_data.get("assigned_user_id", service_order.assigned_user_id),
    )

    for field, value in update_data.items():
        setattr(service_order, field, value)

    apply_service_order_closed_at(service_order, update_data.get("status"))
    apply_service_order_waiting_rule(service_order)
    recalculate_service_order_totals(service_order)
    ensure_service_order_discount_allowed(
        db,
        current_user,
        service_order,
        tenant_company_code(credentials),
    )
    db.commit()
    return get_service_order_or_404(db, service_order.id)


@router.post(
    "/{service_order_id}/items",
    response_model=ServiceOrderItemRead,
    status_code=status.HTTP_201_CREATED,
)
def add_service_order_item(
    service_order_id: int,
    item_in: ServiceOrderItemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:update")),
) -> ServiceOrderItem:
    service_order = get_service_order_or_404(db, service_order_id)
    if item_in.product_id is not None and db.get(Product, item_in.product_id) is None:
        raise HTTPException(status_code=404, detail="Produto/servico nao encontrado.")

    item = ServiceOrderItem(
        **item_in.model_dump(),
        service_order_id=service_order.id,
        total_price=item_in.quantity * item_in.unit_price,
    )
    db.add(item)
    db.flush()
    service_order.items.append(item)
    recalculate_service_order_totals(service_order)
    db.commit()
    db.refresh(item)
    return item


@router.post(
    "/{service_order_id}/thermal-print",
    response_model=ThermalPrintResponse,
)
def print_service_order_thermal(
    service_order_id: int,
    print_in: ThermalPrintRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:view")),
) -> ThermalPrintResponse:
    service_order = get_service_order_or_404(db, service_order_id)
    width = 48 if print_in.paper_width == 80 else 32
    payload = build_service_order_receipt(service_order, width)

    try:
        with socket.create_connection(
            (print_in.printer_host, print_in.printer_port),
            timeout=5,
        ) as printer:
            for _ in range(print_in.copies):
                printer.sendall(payload)
    except OSError as error:
        raise HTTPException(
            status_code=400,
            detail=f"Nao foi possivel imprimir na termica: {error}",
        ) from error

    return ThermalPrintResponse(message="Cupom enviado para a impressora termica.")


@router.delete(
    "/{service_order_id}/items/{item_id}",
    response_model=ServiceOrderRead,
)
def delete_service_order_item(
    service_order_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:update")),
) -> ServiceOrder:
    service_order = get_service_order_or_404(db, service_order_id)
    item = db.get(ServiceOrderItem, item_id)
    if item is None or item.service_order_id != service_order.id:
        raise HTTPException(status_code=404, detail="Item da OS nao encontrado.")
    db.delete(item)
    db.flush()
    recalculate_service_order_totals(service_order)
    db.commit()
    return get_service_order_or_404(db, service_order.id)


@router.delete("/{service_order_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_service_order(
    service_order_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_orders:delete")),
) -> None:
    service_order = get_service_order_or_404(db, service_order_id)
    db.delete(service_order)
    db.commit()

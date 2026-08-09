from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import require_permission
from app.core.database import get_db
from app.models.client import Client
from app.models.equipment import Equipment
from app.models.ticket import Ticket
from app.models.user import User
from app.schemas.ticket import TicketCreate, TicketRead, TicketUpdate

router = APIRouter()


def ensure_ticket_relations(
    db: Session,
    client_id: int | None,
    equipment_id: int | None,
    assigned_user_id: int | None,
) -> None:
    if client_id is not None and db.get(Client, client_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cliente vinculado nao encontrado.",
        )

    if equipment_id is not None:
        equipment = db.get(Equipment, equipment_id)
        if equipment is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Equipamento vinculado nao encontrado.",
            )
        if client_id is not None and equipment.client_id != client_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Equipamento nao pertence ao cliente informado.",
            )

    if assigned_user_id is not None and db.get(User, assigned_user_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tecnico responsavel nao encontrado.",
        )


def apply_closed_at(ticket: Ticket, new_status: str | None) -> None:
    if new_status in {"concluido", "cancelado"} and ticket.closed_at is None:
        ticket.closed_at = datetime.now(UTC)
    if new_status in {"aberto", "em_andamento"}:
        ticket.closed_at = None


@router.post("", response_model=TicketRead, status_code=status.HTTP_201_CREATED)
def create_ticket(
    ticket_in: TicketCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("tickets:create")),
) -> Ticket:
    ensure_ticket_relations(
        db,
        ticket_in.client_id,
        ticket_in.equipment_id,
        ticket_in.assigned_user_id,
    )
    ticket = Ticket(**ticket_in.model_dump())
    apply_closed_at(ticket, ticket.status)
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return ticket


@router.get("", response_model=list[TicketRead])
def list_tickets(
    client_id: int | None = Query(default=None),
    equipment_id: int | None = Query(default=None),
    ticket_status: str | None = Query(default=None, alias="status"),
    priority: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("tickets:view")),
) -> list[Ticket]:
    query = select(Ticket).order_by(Ticket.opened_at.desc())

    if client_id is not None:
        query = query.where(Ticket.client_id == client_id)
    if equipment_id is not None:
        query = query.where(Ticket.equipment_id == equipment_id)
    if ticket_status is not None:
        query = query.where(Ticket.status == ticket_status)
    if priority is not None:
        query = query.where(Ticket.priority == priority)

    return list(db.scalars(query).all())


@router.get("/{ticket_id}", response_model=TicketRead)
def get_ticket(
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("tickets:view")),
) -> Ticket:
    ticket = db.get(Ticket, ticket_id)
    if ticket is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chamado nao encontrado.",
        )
    return ticket


@router.put("/{ticket_id}", response_model=TicketRead)
def update_ticket(
    ticket_id: int,
    ticket_in: TicketUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("tickets:update")),
) -> Ticket:
    ticket = db.get(Ticket, ticket_id)
    if ticket is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chamado nao encontrado.",
        )

    update_data = ticket_in.model_dump(exclude_unset=True)
    next_client_id = update_data.get("client_id", ticket.client_id)
    next_equipment_id = update_data.get("equipment_id", ticket.equipment_id)
    next_assigned_user_id = update_data.get("assigned_user_id", ticket.assigned_user_id)

    ensure_ticket_relations(
        db,
        next_client_id,
        next_equipment_id,
        next_assigned_user_id,
    )

    for field, value in update_data.items():
        setattr(ticket, field, value)

    apply_closed_at(ticket, update_data.get("status"))
    db.commit()
    db.refresh(ticket)
    return ticket


@router.delete("/{ticket_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_ticket(
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("tickets:finish")),
) -> None:
    ticket = db.get(Ticket, ticket_id)
    if ticket is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chamado nao encontrado.",
        )

    db.delete(ticket)
    db.commit()

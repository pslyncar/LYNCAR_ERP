from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.core.security import generate_agent_token, hash_agent_token
from app.models.client import Client
from app.models.equipment import Equipment
from app.models.user import User
from app.schemas.equipment import (
    EquipmentAgentTokenRead,
    EquipmentCreate,
    EquipmentRead,
    EquipmentUpdate,
)

router = APIRouter()


def ensure_client_exists(db: Session, client_id: int) -> None:
    if db.get(Client, client_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cliente vinculado nao encontrado.",
        )


@router.post("", response_model=EquipmentRead, status_code=status.HTTP_201_CREATED)
def create_equipment(
    equipment_in: EquipmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("equipments:create")),
) -> Equipment:
    ensure_client_exists(db, equipment_in.client_id)
    equipment = Equipment(**equipment_in.model_dump())
    db.add(equipment)
    db.commit()
    db.refresh(equipment)
    return equipment


@router.get("", response_model=list[EquipmentRead])
def list_equipments(
    client_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "equipments:view",
            "monitoring:view",
            "service_orders:view",
            "service_orders:create",
            "tickets:view",
            "tickets:create",
        )
    ),
) -> list[Equipment]:
    query = select(Equipment).order_by(Equipment.hostname)
    if client_id is not None:
        query = query.where(Equipment.client_id == client_id)
    return list(db.scalars(query).all())


@router.get("/{equipment_id}", response_model=EquipmentRead)
def get_equipment(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission(
            "equipments:view",
            "monitoring:view",
            "service_orders:view",
            "service_orders:create",
            "tickets:view",
            "tickets:create",
        )
    ),
) -> Equipment:
    equipment = db.get(Equipment, equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )
    return equipment


@router.put("/{equipment_id}", response_model=EquipmentRead)
def update_equipment(
    equipment_id: int,
    equipment_in: EquipmentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("equipments:update")),
) -> Equipment:
    equipment = db.get(Equipment, equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )

    update_data = equipment_in.model_dump(exclude_unset=True)
    if "client_id" in update_data:
        ensure_client_exists(db, update_data["client_id"])

    for field, value in update_data.items():
        setattr(equipment, field, value)

    db.commit()
    db.refresh(equipment)
    return equipment


@router.delete("/{equipment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_equipment(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("equipments:delete")),
) -> None:
    equipment = db.get(Equipment, equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )

    db.delete(equipment)
    db.commit()


@router.post("/{equipment_id}/agent-token", response_model=EquipmentAgentTokenRead)
def generate_equipment_agent_token(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("equipments:update")),
) -> EquipmentAgentTokenRead:
    equipment = db.get(Equipment, equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )

    token = generate_agent_token()
    equipment.agent_token_hash = hash_agent_token(token)
    db.commit()

    return EquipmentAgentTokenRead(
        equipment_id=equipment.id,
        token=token,
        message=(
            "Token gerado. Ele sera exibido apenas uma vez; use no arquivo "
            "de configuracao do agente instalado na maquina do cliente."
        ),
    )

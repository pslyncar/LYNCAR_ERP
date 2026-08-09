from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import require_permission
from app.core.database import get_db
from app.core.security import verify_agent_token
from app.models.equipment import Equipment
from app.models.equipment_status import EquipmentCurrentStatus
from app.models.monitoring import Alert
from app.models.monitoring import MonitoringSnapshot
from app.models.user import User
from app.schemas.monitoring import MonitoringSnapshotCreate, MonitoringSnapshotRead
from app.schemas.equipment_status import AlertRead, EquipmentCurrentStatusRead
from app.services.monitoring_health import (
    build_snapshot,
    create_alerts_if_needed,
    prune_old_snapshots,
    should_store_snapshot,
    update_current_status,
)

router = APIRouter()

SNAPSHOT_IDENTITY_FIELDS = {
    "hostname",
    "operating_system",
    "ip_address",
    "agent_version",
    "logged_user",
}


def update_equipment_identity(
    equipment: Equipment,
    snapshot_in: MonitoringSnapshotCreate,
) -> None:
    if snapshot_in.hostname and not equipment.hostname:
        equipment.hostname = snapshot_in.hostname
    if snapshot_in.operating_system:
        equipment.operating_system = snapshot_in.operating_system
    if snapshot_in.ip_address:
        equipment.last_ip_address = snapshot_in.ip_address
    if snapshot_in.agent_version:
        equipment.agent_version = snapshot_in.agent_version
    if snapshot_in.logged_user:
        equipment.last_logged_user = snapshot_in.logged_user


@router.post(
    "/snapshots",
    response_model=MonitoringSnapshotRead,
    status_code=status.HTTP_201_CREATED,
)
def create_monitoring_snapshot(
    snapshot_in: MonitoringSnapshotCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("monitoring:write")),
) -> MonitoringSnapshot:
    equipment = db.get(Equipment, snapshot_in.equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )

    equipment.last_seen_at = snapshot_in.collected_at
    update_equipment_identity(equipment, snapshot_in)
    if equipment.status == "offline":
        equipment.status = "ativo"

    update_current_status(db, snapshot_in)
    create_alerts_if_needed(db, snapshot_in)
    snapshot = build_snapshot(snapshot_in)
    db.add(snapshot)
    db.flush()
    prune_old_snapshots(db, snapshot_in.equipment_id)
    db.commit()
    db.refresh(snapshot)
    return snapshot


@router.get("/snapshots", response_model=list[MonitoringSnapshotRead])
def list_monitoring_snapshots(
    equipment_id: int,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("monitoring:view")),
) -> list[MonitoringSnapshot]:
    query = (
        select(MonitoringSnapshot)
        .where(MonitoringSnapshot.equipment_id == equipment_id)
        .order_by(MonitoringSnapshot.collected_at.desc())
        .limit(min(limit, 3))
    )
    return list(db.scalars(query).all())


@router.get("/current-status", response_model=EquipmentCurrentStatusRead | None)
def get_current_status(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("monitoring:view")),
) -> EquipmentCurrentStatus | None:
    return db.get(EquipmentCurrentStatus, equipment_id)


@router.get("/alerts", response_model=list[AlertRead])
def list_alerts(
    equipment_id: int | None = None,
    unresolved_only: bool = True,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("monitoring:view")),
) -> list[Alert]:
    query = select(Alert).order_by(Alert.created_at.desc()).limit(min(limit, 200))
    if equipment_id is not None:
        query = query.where(Alert.equipment_id == equipment_id)
    if unresolved_only:
        query = query.where(Alert.resolved.is_(False))
    return list(db.scalars(query).all())


@router.post(
    "/agent/snapshots",
    status_code=status.HTTP_202_ACCEPTED,
)
def create_agent_monitoring_snapshot(
    snapshot_in: MonitoringSnapshotCreate,
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
    db: Session = Depends(get_db),
) -> dict[str, object]:
    equipment = db.get(Equipment, snapshot_in.equipment_id)
    if equipment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Equipamento nao encontrado.",
        )

    if x_agent_token is None or not verify_agent_token(
        x_agent_token,
        equipment.agent_token_hash,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token do agente invalido.",
        )

    equipment.last_seen_at = snapshot_in.collected_at
    update_equipment_identity(equipment, snapshot_in)
    if equipment.status == "offline":
        equipment.status = "ativo"

    current_status = update_current_status(db, snapshot_in)
    alerts = create_alerts_if_needed(db, snapshot_in)
    if should_store_snapshot(snapshot_in):
        snapshot = build_snapshot(snapshot_in)
        db.add(snapshot)
        db.flush()
        prune_old_snapshots(db, snapshot_in.equipment_id)
    db.commit()
    return {
        "status": "accepted",
        "equipment_id": equipment.id,
        "health_status": current_status.health_status,
        "alerts_count": len(alerts),
        "stored_history": should_store_snapshot(snapshot_in),
    }

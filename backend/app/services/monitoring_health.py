from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.equipment_status import EquipmentCurrentStatus
from app.models.monitoring import Alert, MonitoringSnapshot
from app.schemas.monitoring import MonitoringSnapshotCreate

DISK_WARNING_PERCENT = Decimal("80")
DISK_CRITICAL_PERCENT = Decimal("90")
MEMORY_WARNING_PERCENT = Decimal("85")
MEMORY_CRITICAL_PERCENT = Decimal("95")
CPU_WARNING_PERCENT = Decimal("85")
CPU_CRITICAL_PERCENT = Decimal("95")
TEMPERATURE_WARNING_CELSIUS = Decimal("75")
TEMPERATURE_CRITICAL_CELSIUS = Decimal("85")
MAX_CRITICAL_HISTORY_PER_EQUIPMENT = 3


def update_current_status(
    db: Session,
    snapshot_in: MonitoringSnapshotCreate,
) -> EquipmentCurrentStatus:
    health_status = get_health_status(snapshot_in)
    current_status = db.get(EquipmentCurrentStatus, snapshot_in.equipment_id)
    if current_status is None:
        current_status = EquipmentCurrentStatus(
            equipment_id=snapshot_in.equipment_id,
            cpu_usage_percent=snapshot_in.cpu_usage_percent,
            memory_usage_percent=snapshot_in.memory_usage_percent,
            disk_usage_percent=snapshot_in.disk_usage_percent,
            storage_volumes=[volume.model_dump(mode="json") for volume in snapshot_in.storage_volumes],
            temperature_celsius=snapshot_in.temperature_celsius,
            health_status=health_status,
            collected_at=snapshot_in.collected_at,
        )
        db.add(current_status)
    else:
        current_status.cpu_usage_percent = snapshot_in.cpu_usage_percent
        current_status.memory_usage_percent = snapshot_in.memory_usage_percent
        current_status.disk_usage_percent = snapshot_in.disk_usage_percent
        current_status.storage_volumes = [
            volume.model_dump(mode="json") for volume in snapshot_in.storage_volumes
        ]
        current_status.temperature_celsius = snapshot_in.temperature_celsius
        current_status.health_status = health_status
        current_status.collected_at = snapshot_in.collected_at

    return current_status


def create_alerts_if_needed(
    db: Session,
    snapshot_in: MonitoringSnapshotCreate,
) -> list[Alert]:
    alert_specs = get_alert_specs(snapshot_in)
    active_types = {alert_type for alert_type, _, _, _ in alert_specs}
    alerts: list[Alert] = []

    open_alerts = list(
        db.scalars(
            select(Alert).where(
                Alert.equipment_id == snapshot_in.equipment_id,
                Alert.resolved.is_(False),
            )
        ).all()
    )
    for open_alert in open_alerts:
        if open_alert.type not in active_types:
            open_alert.resolved = True
            open_alert.resolved_at = datetime.now(UTC)

    for alert_type, severity, message, metric_value in alert_specs:
        existing_open_alert = next(
            (alert for alert in open_alerts if alert.type == alert_type),
            None,
        )
        if existing_open_alert is not None:
            existing_open_alert.severity = severity
            existing_open_alert.message = message
            existing_open_alert.metric_value = metric_value
            alerts.append(existing_open_alert)
            continue

        alert = Alert(
            equipment_id=snapshot_in.equipment_id,
            type=alert_type,
            severity=severity,
            message=message,
            metric_value=metric_value,
        )
        db.add(alert)
        alerts.append(alert)

    return alerts


def should_store_snapshot(snapshot_in: MonitoringSnapshotCreate) -> bool:
    return any(severity == "critical" for _, severity, _, _ in get_alert_specs(snapshot_in))


def build_snapshot(snapshot_in: MonitoringSnapshotCreate) -> MonitoringSnapshot:
    return MonitoringSnapshot(
        equipment_id=snapshot_in.equipment_id,
        cpu_usage_percent=snapshot_in.cpu_usage_percent,
        memory_usage_percent=snapshot_in.memory_usage_percent,
        disk_usage_percent=snapshot_in.disk_usage_percent,
        temperature_celsius=snapshot_in.temperature_celsius,
        collected_at=snapshot_in.collected_at,
    )


def prune_old_snapshots(
    db: Session,
    equipment_id: int,
    keep: int = MAX_CRITICAL_HISTORY_PER_EQUIPMENT,
) -> None:
    old_snapshots = list(
        db.scalars(
            select(MonitoringSnapshot)
            .where(MonitoringSnapshot.equipment_id == equipment_id)
            .order_by(MonitoringSnapshot.collected_at.desc())
            .offset(keep)
        ).all()
    )
    for snapshot in old_snapshots:
        db.delete(snapshot)


def get_health_status(snapshot_in: MonitoringSnapshotCreate) -> str:
    specs = get_alert_specs(snapshot_in)
    if any(severity == "critical" for _, severity, _, _ in specs):
        return "critical"
    if specs:
        return "warning"
    return "ok"


def get_alert_specs(
    snapshot_in: MonitoringSnapshotCreate,
) -> list[tuple[str, str, str, Decimal]]:
    specs: list[tuple[str, str, str, Decimal]] = []

    specs.extend(
        threshold_alert(
            alert_type="disk_usage",
            label="Armazenamento",
            value=snapshot_in.disk_usage_percent,
            warning=DISK_WARNING_PERCENT,
            critical=DISK_CRITICAL_PERCENT,
        )
    )
    specs.extend(
        threshold_alert(
            alert_type="memory_usage",
            label="Memoria RAM",
            value=snapshot_in.memory_usage_percent,
            warning=MEMORY_WARNING_PERCENT,
            critical=MEMORY_CRITICAL_PERCENT,
        )
    )
    specs.extend(
        threshold_alert(
            alert_type="cpu_usage",
            label="CPU",
            value=snapshot_in.cpu_usage_percent,
            warning=CPU_WARNING_PERCENT,
            critical=CPU_CRITICAL_PERCENT,
        )
    )

    if snapshot_in.temperature_celsius is not None:
        specs.extend(
            threshold_alert(
                alert_type="temperature",
                label="Temperatura",
                value=snapshot_in.temperature_celsius,
                warning=TEMPERATURE_WARNING_CELSIUS,
                critical=TEMPERATURE_CRITICAL_CELSIUS,
                suffix="C",
            )
        )

    return specs


def threshold_alert(
    alert_type: str,
    label: str,
    value: Decimal,
    warning: Decimal,
    critical: Decimal,
    suffix: str = "%",
) -> list[tuple[str, str, str, Decimal]]:
    if value >= critical:
        return [
            (
                alert_type,
                "critical",
                f"{label} em {value}{suffix}. Limite critico: {critical}{suffix}.",
                value,
            )
        ]
    if value >= warning:
        return [
            (
                alert_type,
                "warning",
                f"{label} em {value}{suffix}. Limite de aviso: {warning}{suffix}.",
                value,
            )
        ]
    return []

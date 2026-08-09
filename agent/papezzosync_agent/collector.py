from datetime import UTC, datetime
import getpass
import json
import platform
import socket
import subprocess

import psutil

AGENT_VERSION = "0.1.5"


def collect_snapshot(
    equipment_id: int,
    collect_logged_user: bool = False,
) -> dict[str, object]:
    cpu_usage = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    storage_volumes = collect_storage_volumes()
    storage_usage_percent = max(
        (volume["usage_percent"] for volume in storage_volumes),
        default=0,
    )

    snapshot: dict[str, object] = {
        "equipment_id": equipment_id,
        "cpu_usage_percent": round(cpu_usage, 2),
        "memory_usage_percent": round(memory.percent, 2),
        "disk_usage_percent": round(float(storage_usage_percent), 2),
        "storage_volumes": storage_volumes,
        "temperature_celsius": collect_temperature(),
        "collected_at": datetime.now(UTC).isoformat(),
        "hostname": socket.gethostname(),
        "operating_system": platform.platform(),
        "ip_address": get_primary_ip_address(),
        "agent_version": AGENT_VERSION,
    }

    if collect_logged_user:
        snapshot["logged_user"] = getpass.getuser()

    return snapshot


def collect_storage_volumes() -> list[dict[str, object]]:
    volumes: list[dict[str, object]] = []
    for partition in psutil.disk_partitions(all=False):
        if not should_collect_partition(partition):
            continue
        try:
            usage = psutil.disk_usage(partition.mountpoint)
        except OSError:
            continue

        total_gb = bytes_to_gb(usage.total)
        used_gb = bytes_to_gb(usage.used)
        free_gb = bytes_to_gb(usage.free)
        volumes.append(
            {
                "device": partition.device or partition.mountpoint,
                "mountpoint": partition.mountpoint,
                "filesystem": partition.fstype,
                "total_gb": total_gb,
                "used_gb": used_gb,
                "free_gb": free_gb,
                "usage_percent": round(float(usage.percent), 2),
            }
        )

    return volumes


def should_collect_partition(partition: object) -> bool:
    opts = getattr(partition, "opts", "") or ""
    if "cdrom" in opts.lower():
        return False
    if not getattr(partition, "fstype", ""):
        return False
    return True


def bytes_to_gb(value: int) -> float:
    return round(value / (1024**3), 2)


def get_primary_ip_address() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return None


def collect_temperature() -> float | None:
    temperature = collect_psutil_temperature()
    if temperature is not None:
        return temperature

    if platform.system().lower() == "windows":
        return collect_windows_temperature()

    return None


def collect_psutil_temperature() -> float | None:
    try:
        temperatures = psutil.sensors_temperatures()
    except (AttributeError, OSError):
        return None

    for entries in temperatures.values():
        for entry in entries:
            if entry.current is not None:
                return round(float(entry.current), 2)

    return None


def collect_windows_temperature() -> float | None:
    return collect_windows_acpi_temperature()


def collect_windows_acpi_temperature() -> float | None:
    command = (
        "Get-CimInstance "
        "-Namespace 'root\\wmi' "
        "-ClassName 'MSAcpi_ThermalZoneTemperature' "
        "-ErrorAction SilentlyContinue | "
        "Select-Object CurrentTemperature | ConvertTo-Json -Compress"
    )
    data = run_powershell_json(command)
    if data is None:
        return None

    readings = data if isinstance(data, list) else [data]
    candidates: list[float] = []
    for reading in readings:
        if not isinstance(reading, dict):
            continue
        raw_value = parse_float(reading.get("CurrentTemperature"))
        if raw_value is None:
            continue
        celsius = (raw_value / 10) - 273.15
        if 0 < celsius < 125:
            candidates.append(celsius)

    if not candidates:
        return None
    return round(max(candidates), 2)


def run_powershell_json(command: str, timeout_seconds: int = 3) -> object | None:
    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                command,
            ],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None

    output = result.stdout.strip()
    if result.returncode != 0 or not output:
        return None

    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return None


def parse_float(value: object) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

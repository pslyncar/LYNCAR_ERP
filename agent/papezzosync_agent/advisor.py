from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
import subprocess

import psutil

from papezzosync_agent.config import AgentConfig

CPU_WARNING_PERCENT = 85
MEMORY_WARNING_PERCENT = 85
STORAGE_WARNING_PERCENT = 80


@dataclass(frozen=True)
class LocalAdvice:
    key: str
    title: str
    message: str


def run_local_advisor(config: AgentConfig, snapshot: dict[str, object]) -> None:
    if not config.local_notifications_enabled:
        return

    advices = build_advices(snapshot)
    if not advices:
        return

    state = load_notification_state()
    changed = False
    now = datetime.now(UTC)
    cooldown = timedelta(minutes=config.notification_cooldown_minutes)

    for advice in advices:
        last_sent = parse_datetime(state.get(advice.key))
        if last_sent is not None and now - last_sent < cooldown:
            continue

        notify_user(advice.title, advice.message)
        state[advice.key] = now.isoformat()
        changed = True

    if changed:
        save_notification_state(state)


def build_advices(snapshot: dict[str, object]) -> list[LocalAdvice]:
    advices: list[LocalAdvice] = []
    cpu_usage = as_float(snapshot.get("cpu_usage_percent"))
    memory_usage = as_float(snapshot.get("memory_usage_percent"))
    storage_usage = as_float(snapshot.get("disk_usage_percent"))

    if cpu_usage is not None and cpu_usage >= CPU_WARNING_PERCENT:
        advices.append(
            LocalAdvice(
                key="cpu_high",
                title="PapezzoSync: CPU alta",
                message=(
                    f"A CPU esta em {cpu_usage:.0f}%. "
                    f"Programas usando mais recursos: {format_process_names('cpu')}.\n\n"
                    "O que fazer: salve seu trabalho, feche apenas programas que voce reconhece "
                    "e nao esta usando, e aguarde alguns minutos. O PapezzoSync nao fecha nada sozinho."
                ),
            )
        )

    if memory_usage is not None and memory_usage >= MEMORY_WARNING_PERCENT:
        advices.append(
            LocalAdvice(
                key="memory_high",
                title="PapezzoSync: memoria RAM alta",
                message=(
                    f"A memoria RAM esta em {memory_usage:.0f}%. "
                    f"Programas consumindo mais memoria: {format_process_names('memory')}.\n\n"
                    "O que fazer: salve arquivos abertos e feche apenas programas que voce nao precisa agora. "
                    "Se acontecer sempre, avise o suporte para avaliarmos upgrade de RAM."
                ),
            )
        )

    if storage_usage is not None and storage_usage >= STORAGE_WARNING_PERCENT:
        advices.append(
            LocalAdvice(
                key="storage_high",
                title="PapezzoSync: armazenamento cheio",
                message=(
                    f"O armazenamento chegou a {storage_usage:.0f}% de uso.\n\n"
                    "O que fazer: antes de apagar qualquer coisa, fale com o suporte ou faca backup. "
                    "Voce pode esvaziar a Lixeira, remover programas que nao usa e executar a Limpeza de Disco do Windows. "
                    "O PapezzoSync nao apaga arquivos automaticamente."
                ),
            )
        )

    return advices


def format_process_names(kind: str) -> str:
    processes = collect_top_process_names(kind)
    if not processes:
        return "nao foi possivel identificar com seguranca"
    return ", ".join(processes)


def collect_top_process_names(kind: str) -> list[str]:
    if kind == "cpu":
        for process in psutil.process_iter():
            try:
                process.cpu_percent(interval=None)
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
        try:
            psutil.cpu_percent(interval=0.25)
        except OSError:
            pass

    entries: list[tuple[float, str]] = []

    for process in psutil.process_iter(["name", "memory_percent"]):
        try:
            name = process.info.get("name") or f"PID {process.pid}"
            if kind == "memory":
                score = float(process.info.get("memory_percent") or 0)
            else:
                score = float(process.cpu_percent(interval=None) or 0)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

        if score <= 0:
            continue
        entries.append((score, normalize_process_name(name)))

    unique_names: list[str] = []
    for _, name in sorted(entries, reverse=True):
        if name not in unique_names:
            unique_names.append(name)
        if len(unique_names) == 4:
            break

    return unique_names


def normalize_process_name(name: str) -> str:
    return Path(name).name[:60]


def notify_user(title: str, message: str) -> None:
    if not try_windows_popup(title, message):
        print(f"{title}\n{message}")


def try_windows_popup(title: str, message: str) -> bool:
    escaped_title = json.dumps(title)
    escaped_message = json.dumps(message)
    command = (
        "$shell = New-Object -ComObject WScript.Shell; "
        f"$null = $shell.Popup({escaped_message}, 20, {escaped_title}, 64)"
    )
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
            timeout=25,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def load_notification_state() -> dict[str, str]:
    path = notification_state_path()
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(key): str(value) for key, value in data.items()}


def save_notification_state(state: dict[str, str]) -> None:
    path = notification_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")


def notification_state_path() -> Path:
    return Path.home() / "AppData" / "Local" / "PapezzoSync" / "Agent" / "notification_state.json"


def parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed


def as_float(value: object) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

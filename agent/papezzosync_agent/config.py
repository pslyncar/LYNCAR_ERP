import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class AgentConfig:
    api_base_url: str
    equipment_id: int
    agent_token: str
    interval_seconds: int = 60
    collect_logged_user: bool = False
    local_notifications_enabled: bool = True
    notification_cooldown_minutes: int = 30


def load_config(path: str | Path = "config.json") -> AgentConfig:
    config_path = Path(path)
    if not config_path.exists():
        raise FileNotFoundError(
            f"Arquivo de configuracao nao encontrado: {config_path.resolve()}"
        )

    data = json.loads(config_path.read_text(encoding="utf-8-sig"))
    return AgentConfig(
        api_base_url=str(data["api_base_url"]).rstrip("/"),
        equipment_id=int(data["equipment_id"]),
        agent_token=str(data["agent_token"]),
        interval_seconds=int(data.get("interval_seconds", 60)),
        collect_logged_user=bool(data.get("collect_logged_user", False)),
        local_notifications_enabled=bool(
            data.get("local_notifications_enabled", True)
        ),
        notification_cooldown_minutes=int(
            data.get("notification_cooldown_minutes", 30)
        ),
    )

import requests

from papezzosync_agent.config import AgentConfig


def send_snapshot(config: AgentConfig, snapshot: dict[str, object]) -> None:
    response = requests.post(
        f"{config.api_base_url}/monitoring/agent/snapshots",
        json=snapshot,
        headers={"X-Agent-Token": config.agent_token},
        timeout=15,
    )
    response.raise_for_status()

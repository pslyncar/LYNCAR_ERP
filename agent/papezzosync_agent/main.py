import argparse
import time

from papezzosync_agent.advisor import run_local_advisor
from papezzosync_agent.collector import collect_snapshot
from papezzosync_agent.config import AgentConfig, load_config
from papezzosync_agent.sender import send_snapshot


def resolve_config(args: argparse.Namespace) -> AgentConfig:
    if args.api_base_url and args.equipment_id and args.agent_token:
        return AgentConfig(
            api_base_url=args.api_base_url.rstrip("/"),
            equipment_id=int(args.equipment_id),
            agent_token=args.agent_token,
            interval_seconds=int(args.interval_seconds),
            collect_logged_user=bool(args.collect_logged_user),
            local_notifications_enabled=not args.disable_local_notifications,
            notification_cooldown_minutes=int(args.notification_cooldown_minutes),
        )
    return load_config(args.config)


def run_once(args: argparse.Namespace) -> None:
    config = resolve_config(args)
    snapshot = collect_snapshot(config.equipment_id, config.collect_logged_user)
    send_snapshot(config, snapshot)
    run_local_advisor(config, snapshot)
    print("Snapshot enviado com sucesso.")


def run_loop(args: argparse.Namespace) -> None:
    config = resolve_config(args)
    print("PapezzoSync Agent iniciado.")
    print(f"Equipamento: {config.equipment_id}")
    print(f"Intervalo: {config.interval_seconds}s")

    while True:
        try:
            snapshot = collect_snapshot(config.equipment_id, config.collect_logged_user)
            send_snapshot(config, snapshot)
            run_local_advisor(config, snapshot)
            print("Snapshot enviado com sucesso.")
        except Exception as error:
            print(f"Falha ao enviar snapshot: {error}")

        time.sleep(config.interval_seconds)


def main() -> None:
    parser = argparse.ArgumentParser(description="Agente PapezzoSync")
    parser.add_argument("--config", default="config.json")
    parser.add_argument("--api-base-url", default=None)
    parser.add_argument("--equipment-id", type=int, default=None)
    parser.add_argument("--agent-token", default=None)
    parser.add_argument("--interval-seconds", type=int, default=60)
    parser.add_argument("--collect-logged-user", action="store_true")
    parser.add_argument("--disable-local-notifications", action="store_true")
    parser.add_argument("--notification-cooldown-minutes", type=int, default=30)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    if args.once:
        run_once(args)
    else:
        run_loop(args)


if __name__ == "__main__":
    main()

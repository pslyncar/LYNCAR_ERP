from functools import lru_cache
from pathlib import Path
import os
import json
import secrets

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _default_data_dir() -> Path:
    root = os.environ.get("PROGRAMDATA") or str(Path.home())
    return Path(root) / "Lyncar" / "Edge"


class EdgeSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="LYNCAR_EDGE_",
        env_file=".env",
        extra="ignore",
    )

    cloud_url: str = "http://127.0.0.1:8000"
    access_token: str = Field(default="", repr=False)
    terminal_key: str = Field(default="", repr=False)
    node_key: str = Field(default="", min_length=0, max_length=80)
    lan_key: str = Field(default="", repr=False)
    pairing_code: str = Field(default="", min_length=0, max_length=32, repr=False)
    data_dir: Path = Field(default_factory=_default_data_dir)
    bind_host: str = "0.0.0.0"
    bind_port: int = Field(default=8765, ge=1024, le=65535)
    sync_interval_seconds: int = Field(default=15, ge=2, le=300)
    reconcile_interval_seconds: int = Field(default=900, ge=60, le=86400)
    request_timeout_seconds: int = Field(default=20, ge=3, le=120)

    @property
    def database_path(self) -> Path:
        return self.data_dir / "edge.db"

    @property
    def config_path(self) -> Path:
        return self.data_dir / "config.json"

    @property
    def configured(self) -> bool:
        return all(
            value.strip()
            for value in (self.access_token, self.terminal_key, self.node_key, self.lan_key)
        )

    def ensure_pairing_code(self) -> str:
        if not self.pairing_code:
            self.pairing_code = secrets.token_urlsafe(9).replace("-", "").replace("_", "")[:12].upper()
            self.persist()
        return self.pairing_code

    def load_persisted(self) -> None:
        if not self.config_path.is_file():
            return
        try:
            values = json.loads(self.config_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        for name in ("cloud_url", "access_token", "terminal_key", "node_key", "lan_key", "pairing_code"):
            value = values.get(name)
            if isinstance(value, str) and value:
                setattr(self, name, value)

    def persist(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.config_path.write_text(
            json.dumps(
                {
                    "cloud_url": self.cloud_url,
                    "access_token": self.access_token,
                    "terminal_key": self.terminal_key,
                    "node_key": self.node_key,
                    "lan_key": self.lan_key,
                    "pairing_code": self.pairing_code,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

    def validate_runtime(self) -> None:
        missing = [
            name
            for name, value in {
                "access_token": self.access_token,
                "terminal_key": self.terminal_key,
                "node_key": self.node_key,
                "lan_key": self.lan_key,
            }.items()
            if not value.strip()
        ]
        if missing:
            raise RuntimeError(
                "Configuracao Edge incompleta: " + ", ".join(sorted(missing))
            )


@lru_cache
def get_settings() -> EdgeSettings:
    settings = EdgeSettings()
    settings.load_persisted()
    return settings

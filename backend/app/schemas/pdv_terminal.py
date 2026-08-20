from datetime import datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PdvTerminalRegister(BaseModel):
    cash_register_number: str = Field(min_length=1, max_length=10)
    terminal_key: str = Field(min_length=8, max_length=180)
    app_version: str | None = Field(default=None, max_length=40)
    device_label: str | None = Field(default=None, max_length=120)

    @field_validator("cash_register_number", "terminal_key", mode="before")
    @classmethod
    def clean_required_text(cls, value: object) -> str:
        return str(value or "").strip()

    @field_validator("cash_register_number")
    @classmethod
    def normalize_cash_register_number(cls, value: str) -> str:
        digits = "".join(char for char in value if char.isdigit())
        if not digits:
            raise ValueError("Informe o numero do caixa.")
        return digits.zfill(2)[-10:]


class PdvTerminalHeartbeat(BaseModel):
    terminal_key: str = Field(min_length=8, max_length=180)
    app_version: str | None = Field(default=None, max_length=40)
    device_label: str | None = Field(default=None, max_length=120)
    current_status: str = Field(default="closed", max_length=30)
    current_operator_name: str | None = Field(default=None, max_length=150)
    cash_opened_at: datetime | None = None
    current_session_total_amount: Decimal | None = None

    @field_validator("terminal_key", "current_status", mode="before")
    @classmethod
    def clean_text(cls, value: object) -> str:
        return str(value or "").strip()

    @field_validator("current_status")
    @classmethod
    def validate_status(cls, value: str) -> str:
        status = value.strip().lower()
        if status not in {"open", "paused", "closed"}:
            raise ValueError("Status do PDV invalido.")
        return status


class PdvTerminalNumberUpdate(BaseModel):
    cash_register_number: str = Field(min_length=1, max_length=10)

    @field_validator("cash_register_number", mode="before")
    @classmethod
    def clean_number(cls, value: object) -> str:
        return str(value or "").strip()

    @field_validator("cash_register_number")
    @classmethod
    def normalize_cash_register_number(cls, value: str) -> str:
        digits = "".join(char for char in value if char.isdigit())
        if not digits:
            raise ValueError("Informe o numero do caixa.")
        return digits.zfill(2)[-10:]


class PdvTerminalActivationCreate(BaseModel):
    cash_register_number: str = Field(min_length=1, max_length=10)
    device_label: str | None = Field(default=None, max_length=120)
    expires_hours: int = Field(default=24, ge=1, le=168)

    @field_validator("cash_register_number", mode="before")
    @classmethod
    def clean_number(cls, value: object) -> str:
        return str(value or "").strip()

    @field_validator("cash_register_number")
    @classmethod
    def normalize_cash_register_number(cls, value: str) -> str:
        digits = "".join(char for char in value if char.isdigit())
        if not digits:
            raise ValueError("Informe o numero do caixa.")
        return digits.zfill(2)[-10:]

    @field_validator("device_label", mode="before")
    @classmethod
    def clean_optional_text(cls, value: object) -> str | None:
        text = str(value or "").strip()
        return text or None


class MasterPdvTerminalActivationCreate(PdvTerminalActivationCreate):
    company_code: str = Field(min_length=1, max_length=80)

    @field_validator("company_code", mode="before")
    @classmethod
    def clean_company_code(cls, value: object) -> str:
        return str(value or "").strip().lower()


class PdvTerminalActivationCodeRead(BaseModel):
    terminal: "PdvTerminalRead"
    activation_code: str
    expires_at: datetime


class PdvTerminalActivationRequest(BaseModel):
    activation_code: str = Field(min_length=6, max_length=40)
    app_version: str | None = Field(default=None, max_length=40)
    device_label: str | None = Field(default=None, max_length=120)
    machine_name: str | None = Field(default=None, max_length=120)
    windows_user: str | None = Field(default=None, max_length=120)
    windows_version: str | None = Field(default=None, max_length=120)
    device_fingerprint: str | None = Field(default=None, max_length=180)

    @field_validator(
        "activation_code",
        "app_version",
        "device_label",
        "machine_name",
        "windows_user",
        "windows_version",
        "device_fingerprint",
        mode="before",
    )
    @classmethod
    def clean_text(cls, value: object) -> str | None:
        text = str(value or "").strip()
        return text or None


class PdvTerminalRead(BaseModel):
    id: int
    cash_register_number: str
    terminal_key: str
    app_version: str | None
    device_label: str | None
    activation_status: str = "active"
    activation_code_expires_at: datetime | None = None
    activated_at: datetime | None = None
    machine_name: str | None = None
    windows_user: str | None = None
    windows_version: str | None = None
    device_fingerprint: str | None = None
    active: bool
    current_status: str | None
    current_operator_name: str | None
    cash_opened_at: datetime | None
    current_session_total_amount: Decimal | None
    today_sales_count: int = 0
    today_sales_amount: Decimal = Decimal("0")
    created_at: datetime
    updated_at: datetime | None
    last_seen_at: datetime | None
    crossed_business_day: bool = False

    model_config = ConfigDict(from_attributes=True)


class PdvBusinessDaySettings(BaseModel):
    cutoff_minutes: int = Field(default=180, ge=0, le=1439)


class PdvTerminalCommandCreate(BaseModel):
    action: str = Field(min_length=1, max_length=40)
    message: str | None = Field(default=None, max_length=240)
    payload: dict[str, Any] | None = None

    @field_validator("action", mode="before")
    @classmethod
    def clean_action(cls, value: object) -> str:
        return str(value or "").strip().lower()

    @field_validator("action")
    @classmethod
    def validate_action(cls, value: str) -> str:
        if value not in {
            "force_reconnect",
            "sync_offline_sales",
            "clear_local_queue",
            "block_terminal",
            "unblock_terminal",
            "reset_terminal_link",
            "request_update",
            "reload_catalog",
        }:
            raise ValueError("Comando do terminal invalido.")
        return value

    @field_validator("message", mode="before")
    @classmethod
    def clean_optional_message(cls, value: object) -> str | None:
        text = str(value or "").strip()
        return text or None


class PdvTerminalCommandAck(BaseModel):
    terminal_key: str = Field(min_length=8, max_length=180)
    status: str = Field(min_length=1, max_length=20)
    result_message: str | None = Field(default=None, max_length=2000)

    @field_validator("terminal_key", "status", mode="before")
    @classmethod
    def clean_required_text(cls, value: object) -> str:
        return str(value or "").strip()

    @field_validator("status")
    @classmethod
    def validate_status(cls, value: str) -> str:
        status = value.strip().lower()
        if status not in {"done", "failed"}:
            raise ValueError("Status do comando invalido.")
        return status

    @field_validator("result_message", mode="before")
    @classmethod
    def clean_result_message(cls, value: object) -> str | None:
        text = str(value or "").strip()
        return text or None


class PdvTerminalCommandRead(BaseModel):
    id: int
    terminal_id: int
    action: str
    status: str
    message: str | None = None
    payload: dict[str, Any] | None = None
    result_message: str | None = None
    created_at: datetime
    delivered_at: datetime | None = None
    completed_at: datetime | None = None

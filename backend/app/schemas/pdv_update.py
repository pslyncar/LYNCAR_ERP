from datetime import datetime

from pydantic import BaseModel, Field


class PdvAppVersionCreate(BaseModel):
    version: str = Field(min_length=1, max_length=40)
    build_number: int = 0
    platform: str = "windows"
    channel: str = "stable"
    file_url: str = Field(min_length=1)
    file_sha256: str = Field(min_length=32, max_length=128)
    file_size: int | None = None
    required: bool = False
    active: bool = True
    min_supported_version: str | None = None
    release_notes: str | None = None
    released_at: datetime | None = None


class PdvAppVersionRead(PdvAppVersionCreate):
    id: int
    created_by: str | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class PdvAppVersionRolloutCreate(BaseModel):
    version_id: int
    company_id: int | None = None
    company_code: str | None = None
    plan: str | None = None
    channel: str = "stable"
    percent: int | None = Field(default=None, ge=0, le=100)
    enabled: bool = True
    mandatory: bool = False


class PdvAppVersionRolloutRead(PdvAppVersionRolloutCreate):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class PdvUpdateCheckResponse(BaseModel):
    update_available: bool
    message: str | None = None
    version: str | None = None
    build_number: int | None = None
    required: bool = False
    mandatory: bool = False
    url: str | None = None
    sha256: str | None = None
    size: int | None = None
    release_notes: str | None = None
    install_when: str = "cashier_closed"

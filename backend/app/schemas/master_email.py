from pydantic import BaseModel, EmailStr, Field


class MasterEmailSettingRead(BaseModel):
    provider: str
    auth_method: str
    smtp_host: str | None = None
    smtp_port: int
    username: str | None = None
    client_id: str | None = None
    from_email: str | None = None
    from_name: str | None = None
    enabled: bool
    password_configured: bool
    client_secret_configured: bool
    refresh_token_configured: bool
    configured: bool


class MasterEmailSettingUpdate(BaseModel):
    auth_method: str = Field(default="smtp", pattern="^(smtp|gmail_api)$")
    smtp_host: str | None = Field(default=None, max_length=180)
    smtp_port: int = Field(default=587, ge=1, le=65535)
    username: str | None = Field(default=None, max_length=180)
    password: str | None = Field(default=None, max_length=1000)
    client_id: str | None = Field(default=None, max_length=240)
    client_secret: str | None = Field(default=None, max_length=1000)
    refresh_token: str | None = Field(default=None, max_length=2000)
    from_email: EmailStr | None = None
    from_name: str | None = Field(default=None, max_length=120)
    enabled: bool = False

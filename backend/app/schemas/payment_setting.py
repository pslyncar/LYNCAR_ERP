from pydantic import BaseModel, Field


class PaymentSettingRead(BaseModel):
    provider: str
    environment: str
    public_key: str | None = None
    access_token_configured: bool = False
    access_token_preview: str | None = None
    webhook_url: str | None = None
    active: bool


class PaymentSettingUpdate(BaseModel):
    environment: str = Field(pattern="^(test|production)$")
    public_key: str | None = None
    access_token: str | None = None
    webhook_url: str | None = None
    active: bool = True

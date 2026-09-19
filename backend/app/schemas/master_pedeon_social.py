from pydantic import BaseModel, Field


class PedeOnSocialProviderRead(BaseModel):
    provider: str
    client_id: str | None = None
    redirect_uri: str | None = None
    enabled: bool
    configured: bool
    client_secret_configured: bool
    extra_configured: bool = False


class PedeOnSocialProviderUpdate(BaseModel):
    provider: str = Field(pattern="^(google|facebook|apple)$")
    client_id: str | None = Field(default=None, max_length=240)
    client_secret: str | None = Field(default=None, max_length=4000)
    redirect_uri: str | None = Field(default=None, max_length=500)
    enabled: bool = False
    extra: dict[str, str | None] = Field(default_factory=dict)

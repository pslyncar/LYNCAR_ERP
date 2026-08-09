from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class WebsiteContactRequestCreate(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    phone: str = Field(min_length=8, max_length=40)
    email: str | None = Field(default=None, max_length=180)
    company_name: str | None = Field(default=None, max_length=180)
    message: str | None = Field(default=None, max_length=2000)
    website: str | None = Field(default=None, max_length=200)

    @field_validator("name", "phone", "email", "company_name", "message", "website", mode="before")
    @classmethod
    def strip_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class WebsiteContactRequestRead(BaseModel):
    id: int
    name: str
    phone: str
    email: str | None
    company_name: str | None
    message: str | None
    status: str
    source: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class WebsiteContactRequestStatusUpdate(BaseModel):
    status: str = Field(pattern="^(new|in_progress|contacted|closed)$")

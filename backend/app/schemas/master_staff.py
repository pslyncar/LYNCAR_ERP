from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class MasterPermissionRead(BaseModel):
    code: str
    label: str
    module: str
    description: str


class MasterStaffRead(BaseModel):
    id: int
    name: str
    email: EmailStr
    active: bool
    must_change_password: bool
    permissions: list[str]
    created_at: datetime


class MasterStaffCreate(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    active: bool = True
    must_change_password: bool = True
    permissions: list[str] = Field(default_factory=list)


class MasterStaffUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=150)
    email: EmailStr | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)
    active: bool | None = None
    must_change_password: bool | None = None
    permissions: list[str] | None = None

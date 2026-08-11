from datetime import datetime
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    email: EmailStr
    seller_code: str | None = Field(default=None, max_length=40)
    technician_code: str | None = Field(default=None, max_length=40)
    password: str = Field(min_length=8, max_length=128)
    role: str = Field(min_length=2, max_length=50)
    active: bool = True
    app_access: bool | None = None
    allow_cross_company_duplicate: bool = False


class UserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=150)
    email: EmailStr | None = None
    seller_code: str | None = Field(default=None, max_length=40)
    technician_code: str | None = Field(default=None, max_length=40)
    password: str | None = Field(default=None, min_length=8, max_length=128)
    role: str | None = Field(default=None, min_length=2, max_length=50)
    active: bool | None = None
    app_access: bool | None = None
    allow_cross_company_duplicate: bool = False


class UserRead(BaseModel):
    id: int
    name: str
    email: EmailStr
    seller_code: str | None
    technician_code: str | None
    role: str
    active: bool
    created_at: datetime
    permissions: list[str] = []

    model_config = ConfigDict(from_attributes=True)


class RoleRead(BaseModel):
    id: int
    name: str
    label: str
    description: str | None
    is_seller_profile: bool = False
    is_technician_profile: bool = False
    active: bool
    permissions: list[str] = []

    model_config = ConfigDict(from_attributes=True)


class RoleCreate(BaseModel):
    label: str = Field(min_length=2, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    permissions: list[str] = []
    is_seller_profile: bool = False
    is_technician_profile: bool = False
    active: bool = True


class RoleUpdate(BaseModel):
    label: str | None = Field(default=None, min_length=2, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    permissions: list[str] | None = None
    is_seller_profile: bool | None = None
    is_technician_profile: bool | None = None
    active: bool | None = None


class PermissionRead(BaseModel):
    id: int
    code: str
    label: str
    module: str
    description: str | None
    active: bool

    model_config = ConfigDict(from_attributes=True)


class UserPermissionSet(BaseModel):
    permission_code: str
    allowed: bool

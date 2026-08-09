from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    company_code: str = Field(min_length=2, max_length=64)
    email: EmailStr
    password: str = Field(min_length=6)


class AutomaticLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    client_type: str | None = Field(default=None, max_length=32)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    company_code: str
    company_name: str
    business_type: str = "custom"
    plan_code: str = "start"
    enabled_modules: list[str] = []
    permissions: list[str]
    must_change_password: bool = False


class CurrentUserRead(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: str
    company_code: str
    company_name: str
    business_type: str = "custom"
    plan_code: str = "start"
    enabled_modules: list[str] = []
    permissions: list[str]


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=6, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class ChangePasswordResponse(BaseModel):
    ok: bool = True

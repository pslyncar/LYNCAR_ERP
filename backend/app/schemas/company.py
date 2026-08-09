from datetime import date, datetime

from pydantic import BaseModel, EmailStr, Field, field_validator


def _parse_contract_date(value: object) -> object:
    if value is None or isinstance(value, date):
        return value
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        if "/" in text:
            try:
                return datetime.strptime(text, "%d/%m/%Y").date()
            except ValueError:
                return value
    return value


class PlanOverride(BaseModel):
    max_users: int | None = Field(default=None, ge=1)
    database_limit_mb: int | None = Field(default=None, ge=1)
    file_limit_mb: int | None = Field(default=None, ge=1)
    multi_company_limit: int | None = Field(default=None, ge=1)
    api_enabled: bool | None = None
    priority_support: bool | None = None


class CompanyRead(BaseModel):
    id: int
    code: str
    name: str
    business_type: str
    person_type: str
    document_number: str | None
    state_registration: str | None
    municipal_registration: str | None = None
    trade_name: str | None
    contact_name: str | None
    responsible_cpf: str | None = None
    responsible_birth_date: date | None = None
    phone: str | None
    email: str | None
    admin_name: str | None = None
    admin_email: str | None = None
    address_line: str | None
    address_number: str | None
    neighborhood: str | None
    city: str | None
    city_code: str | None
    state: str | None
    zip_code: str | None
    tax_regime: str | None
    crt: str | None
    tax_regime_source: str | None
    tax_regime_checked_at: str | None
    cnpj_lookup_status: str | None
    cnpj_lookup_message: str | None
    cnae_main: str | None
    legal_nature: str | None
    company_size: str | None
    database_url: str
    plan: str
    plan_overrides: dict | None
    enabled_modules: list[str]
    monthly_price: str | None
    billing_day: str | None
    payment_method: str | None
    contract_signed_at: date | None
    contract_expires_at: date | None
    contract_file_url: str | None
    contract_file_name: str | None
    contract_notes: str | None
    digital_certificate_configured: bool
    digital_certificate_name: str | None
    digital_certificate_expires_at: str | None
    digital_certificate_notes: str | None
    xml_email_address: str | None = None
    xml_email_enabled: bool = True
    status: str
    active: bool
    notes: str | None
    created_at: datetime
    database_usage_mb: int | None = None
    file_usage_mb: int | None = None
    database_limit_mb: int | None = None
    file_limit_mb: int | None = None

    model_config = {"from_attributes": True}


class CompanyCreate(BaseModel):
    code: str = Field(min_length=2, max_length=64)
    name: str = Field(min_length=2, max_length=180)
    business_type: str = Field(default="custom", max_length=60)
    person_type: str = Field(default="PF", max_length=2)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    municipal_registration: str | None = Field(default=None, max_length=40)
    trade_name: str | None = Field(default=None, max_length=180)
    contact_name: str | None = Field(default=None, max_length=150)
    responsible_cpf: str | None = Field(default=None, max_length=14)
    responsible_birth_date: date | None = None
    phone: str | None = Field(default=None, max_length=40)
    email: EmailStr | None = None
    address_line: str | None = Field(default=None, max_length=180)
    address_number: str | None = Field(default=None, max_length=20)
    neighborhood: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=120)
    city_code: str | None = Field(default=None, max_length=20)
    state: str | None = Field(default=None, max_length=2)
    zip_code: str | None = Field(default=None, max_length=20)
    tax_regime: str | None = Field(default=None, max_length=40)
    crt: str | None = Field(default=None, max_length=10)
    database_url: str | None = None
    plan: str = Field(default="erp", max_length=80)
    plan_overrides: PlanOverride | None = None
    enabled_modules: list[str] | None = None
    monthly_price: str | None = Field(default=None, max_length=30)
    billing_day: str | None = Field(default=None, max_length=2)
    payment_method: str | None = Field(default=None, max_length=40)
    contract_signed_at: date | None = None
    contract_expires_at: date | None = None
    contract_file_url: str | None = Field(default=None, max_length=2000)
    contract_file_name: str | None = Field(default=None, max_length=220)
    contract_notes: str | None = None
    digital_certificate_configured: bool = False
    digital_certificate_name: str | None = Field(default=None, max_length=180)
    digital_certificate_expires_at: str | None = Field(default=None, max_length=30)
    digital_certificate_notes: str | None = None
    xml_email_enabled: bool = True
    status: str = Field(default="active", max_length=30)
    active: bool = True
    notes: str | None = None
    provision_database: bool = True
    admin_name: str = Field(min_length=2, max_length=150)
    admin_email: EmailStr
    admin_password: str = Field(min_length=8, max_length=128)
    allow_cross_company_duplicate: bool = False

    @field_validator("contract_signed_at", "contract_expires_at", "responsible_birth_date", mode="before")
    @classmethod
    def parse_contract_dates(cls, value: object) -> object:
        return _parse_contract_date(value)


class CompanyUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=180)
    business_type: str | None = Field(default=None, max_length=60)
    person_type: str | None = Field(default=None, max_length=2)
    document_number: str | None = Field(default=None, max_length=30)
    state_registration: str | None = Field(default=None, max_length=40)
    municipal_registration: str | None = Field(default=None, max_length=40)
    trade_name: str | None = Field(default=None, max_length=180)
    contact_name: str | None = Field(default=None, max_length=150)
    responsible_cpf: str | None = Field(default=None, max_length=14)
    responsible_birth_date: date | None = None
    phone: str | None = Field(default=None, max_length=40)
    email: EmailStr | None = None
    address_line: str | None = Field(default=None, max_length=180)
    address_number: str | None = Field(default=None, max_length=20)
    neighborhood: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=120)
    city_code: str | None = Field(default=None, max_length=20)
    state: str | None = Field(default=None, max_length=2)
    zip_code: str | None = Field(default=None, max_length=20)
    tax_regime: str | None = Field(default=None, max_length=40)
    crt: str | None = Field(default=None, max_length=10)
    database_url: str | None = None
    plan: str | None = Field(default=None, max_length=80)
    plan_overrides: PlanOverride | None = None
    enabled_modules: list[str] | None = None
    monthly_price: str | None = Field(default=None, max_length=30)
    billing_day: str | None = Field(default=None, max_length=2)
    payment_method: str | None = Field(default=None, max_length=40)
    contract_signed_at: date | None = None
    contract_expires_at: date | None = None
    contract_file_url: str | None = Field(default=None, max_length=2000)
    contract_file_name: str | None = Field(default=None, max_length=220)
    contract_notes: str | None = None
    digital_certificate_configured: bool | None = None
    digital_certificate_name: str | None = Field(default=None, max_length=180)
    digital_certificate_expires_at: str | None = Field(default=None, max_length=30)
    digital_certificate_notes: str | None = None
    xml_email_enabled: bool | None = None
    status: str | None = Field(default=None, max_length=30)
    active: bool | None = None
    notes: str | None = None
    admin_name: str | None = Field(default=None, min_length=2, max_length=150)
    admin_email: EmailStr | None = None
    admin_password: str | None = Field(default=None, min_length=8, max_length=128)
    allow_cross_company_duplicate: bool = False

    @field_validator("contract_signed_at", "contract_expires_at", "responsible_birth_date", mode="before")
    @classmethod
    def parse_contract_dates(cls, value: object) -> object:
        return _parse_contract_date(value)


class CompanyTaxProfileLookup(BaseModel):
    cnpj: str
    found: bool = False
    source: str | None = None
    status: str = "not_found"
    message: str | None = None
    legal_name: str | None = None
    trade_name: str | None = None
    tax_regime: str | None = None
    crt: str | None = None
    is_mei: bool | None = None
    is_simples: bool | None = None
    cnae_main: str | None = None
    cnae_description: str | None = None
    legal_nature: str | None = None
    company_size: str | None = None
    status_reason: str | None = None
    opened_at: str | None = None
    email: str | None = None
    phone: str | None = None
    zip_code: str | None = None
    state: str | None = None
    city: str | None = None
    city_code: str | None = None
    neighborhood: str | None = None
    address_line: str | None = None
    address_number: str | None = None
    address_complement: str | None = None


class CompanyTaxProfileRefreshResult(BaseModel):
    company_id: int
    code: str
    name: str
    document_number: str | None
    updated: bool
    status: str
    message: str | None = None
    tax_regime: str | None = None
    crt: str | None = None
    source: str | None = None


class CompanyTaxProfileRefreshSummary(BaseModel):
    total: int
    updated: int
    skipped: int
    failed: int
    results: list[CompanyTaxProfileRefreshResult]


class CompanyContractRead(BaseModel):
    id: int
    code: str
    name: str
    document_number: str | None = None
    email: str | None = None
    phone: str | None = None
    status: str
    active: bool
    contract_signed_at: date | None = None
    contract_expires_at: date | None = None
    contract_file_url: str | None = None
    contract_file_name: str | None = None
    contract_notes: str | None = None
    days_to_expire: int | None = None
    attention_level: str = "sem_contrato"

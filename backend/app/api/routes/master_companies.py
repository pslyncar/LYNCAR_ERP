import secrets
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import create_engine, func, or_, select, text

from app.api.dependencies import require_master_permission
from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.core.security import hash_password
from app.models.company import Company
from app.models.master_user_index import MasterUserIndex
from app.schemas.company import (
    CompanyCreate,
    CompanyContractRead,
    CompanyRead,
    CompanyTaxProfileLookup,
    CompanyTaxProfileRefreshResult,
    CompanyTaxProfileRefreshSummary,
    CompanyUpdate,
)
from app.services.company_tax_profile import (
    apply_lookup_to_company,
    lookup_company_tax_profile,
)
from app.services.company_modules import modules_for_business_type
from app.services.master_holidays import _resolve_ibge_city_code
from app.services.master_user_index import (
    remove_user_index,
    require_duplicate_authorization,
    upsert_user_index,
)
from app.services.plan_limits import (
    effective_plan_limits,
    normalize_plan_code,
    plan_defaults,
    tenant_file_usage_bytes,
)
from app.services.tenant_provisioning import (
    database_url_for_company,
    provision_tenant_database,
)
from app.services.tenancy import normalize_company_code
from app.services.uploads import UPLOAD_ROOT

router = APIRouter()

RESERVED_COMPANY_CODES = {"api", "app", "erp", "lyncar", "master", "www"}
PAYMENT_METHODS = {
    "pix",
    "boleto",
    "cartao_credito",
    "cartao_debito",
    "dinheiro",
    "transferencia",
    "outro",
}


def _add_contract_months(value: date, months: int = 12) -> date:
    year = value.year + ((value.month - 1 + months) // 12)
    month = ((value.month - 1 + months) % 12) + 1
    day = value.day
    while True:
        try:
            return date(year, month, day)
        except ValueError:
            day -= 1


def _contract_expiration_for(signed_at: date | None, expires_at: date | None) -> date | None:
    if expires_at is not None:
        return expires_at
    if signed_at is None:
        return None
    return _add_contract_months(signed_at, 12)


def _contract_attention_level(expires_at: date | None, today: date | None = None) -> str:
    if expires_at is None:
        return "sem_contrato"
    days = (expires_at - (today or date.today())).days
    if days < 0:
        return "vencido"
    if days <= 40:
        return "atencao_master"
    return "ativo"


def _read_contract(company: Company) -> CompanyContractRead:
    expires_at = company.contract_expires_at
    days = (expires_at - date.today()).days if expires_at is not None else None
    return CompanyContractRead(
        id=company.id,
        code=company.code,
        name=company.name,
        document_number=company.document_number,
        email=company.email,
        phone=company.phone,
        status=company.status,
        active=company.active,
        contract_signed_at=company.contract_signed_at,
        contract_expires_at=expires_at,
        contract_file_url=company.contract_file_url,
        contract_file_name=company.contract_file_name,
        contract_notes=company.contract_notes,
        days_to_expire=days,
        attention_level=_contract_attention_level(expires_at),
    )


def validate_company_code_for_domain(code: str) -> None:
    if code in RESERVED_COMPANY_CODES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Este subdominio e reservado para a plataforma Lyncar.",
        )


def _normalize_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    return normalized or None


def _only_digits(value: str | None) -> str | None:
    if value is None:
        return None
    digits = "".join(char for char in value if char.isdigit())
    return digits or None


def _resolve_company_city_code(
    *,
    city: str | None,
    state: str | None,
    city_code: str | None,
) -> str | None:
    current = _only_digits(city_code)
    if current:
        return current
    if not city or not state:
        return None
    resolved = _resolve_ibge_city_code(city, state)
    return str(resolved) if resolved is not None else None


def _complete_company_city_code(company: Company) -> None:
    resolved = _resolve_company_city_code(
        city=company.city,
        state=company.state,
        city_code=company.city_code,
    )
    if resolved:
        company.city_code = resolved


def _clean_plan_overrides(value) -> dict | None:
    if value is None:
        return None
    data = value.model_dump(exclude_none=True) if hasattr(value, "model_dump") else dict(value)
    data = {key: item for key, item in data.items() if item is not None}
    return data or None


def validate_billing_fields(billing_day: str | None, payment_method: str | None) -> None:
    try:
        day = int((billing_day or "").strip())
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Informe o dia de vencimento da mensalidade.",
        )
    if day < 1 or day > 31:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="O dia de vencimento deve estar entre 1 e 31.",
        )
    method = (payment_method or "").strip()
    if not method:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Selecione a forma de pagamento da mensalidade.",
        )
    if method not in PAYMENT_METHODS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Forma de pagamento invalida.",
        )


def sync_company_fiscal_seed(company: Company) -> None:
    """Preenche o fiscal do tenant com CNPJ/IE/endereco do cadastro master."""
    tenant_engine = create_engine(company.database_url, pool_pre_ping=True)
    values = {
        "legal_name": company.name,
        "trade_name": company.trade_name,
        "cnpj": company.document_number,
        "state_registration": company.state_registration,
        "municipal_registration": getattr(company, "municipal_registration", None),
        "address_line": company.address_line,
        "address_number": company.address_number,
        "neighborhood": company.neighborhood,
        "city": company.city,
        "city_code": company.city_code,
        "state": company.state,
        "zip_code": company.zip_code,
        "tax_regime": company.tax_regime,
        "crt": company.crt,
        "environment": "homologacao",
    }
    try:
        with tenant_engine.begin() as connection:
            connection.execute(
                text(
                    """
                    INSERT INTO company_fiscal_settings (
                        legal_name,
                        trade_name,
                        cnpj,
                        state_registration,
                        municipal_registration,
                        address_line,
                        address_number,
                        neighborhood,
                        city,
                        city_code,
                        uf,
                        zip_code,
                        tax_regime,
                        crt,
                        environment,
                        nfce_enabled,
                        pdv_nfce_enabled,
                        nfe_enabled,
                        nfce_series,
                        nfce_next_number,
                        nfe_series,
                        nfe_next_number
                    )
                    SELECT
                        :legal_name,
                        :trade_name,
                        :cnpj,
                        :state_registration,
                        :municipal_registration,
                        :address_line,
                        :address_number,
                        :neighborhood,
                        :city,
                        :city_code,
                        :state,
                        :zip_code,
                        :tax_regime,
                        :crt,
                        :environment,
                        false,
                        false,
                        false,
                        1,
                        1,
                        1,
                        1
                    WHERE NOT EXISTS (
                        SELECT 1 FROM company_fiscal_settings
                    )
                    """
                ),
                values,
            )
            connection.execute(
                text(
                    """
                    UPDATE company_fiscal_settings
                    SET
                        legal_name = COALESCE(NULLIF(legal_name, ''), :legal_name),
                        trade_name = COALESCE(NULLIF(trade_name, ''), :trade_name),
                        cnpj = COALESCE(NULLIF(cnpj, ''), :cnpj),
                        state_registration = COALESCE(NULLIF(state_registration, ''), :state_registration),
                        municipal_registration = COALESCE(NULLIF(municipal_registration, ''), :municipal_registration),
                        address_line = COALESCE(NULLIF(address_line, ''), :address_line),
                        address_number = COALESCE(NULLIF(address_number, ''), :address_number),
                        neighborhood = COALESCE(NULLIF(neighborhood, ''), :neighborhood),
                        city = COALESCE(NULLIF(city, ''), :city),
                        city_code = CASE
                            WHEN CAST(:city_code AS text) IS NOT NULL AND CAST(:city_code AS text) <> '' THEN CAST(:city_code AS text)
                            ELSE city_code
                        END,
                        uf = COALESCE(NULLIF(uf, ''), :state),
                        zip_code = COALESCE(NULLIF(zip_code, ''), :zip_code),
                        tax_regime = CASE
                            WHEN CAST(:tax_regime AS text) IS NOT NULL AND CAST(:tax_regime AS text) <> '' THEN CAST(:tax_regime AS text)
                            ELSE tax_regime
                        END,
                        crt = CASE
                            WHEN CAST(:crt AS text) IS NOT NULL AND CAST(:crt AS text) <> '' THEN CAST(:crt AS text)
                            ELSE crt
                        END,
                        environment = COALESCE(NULLIF(environment, ''), :environment)
                    """
                ),
                values,
            )
    finally:
        tenant_engine.dispose()


def ensure_unique_company(
    db,
    *,
    name: str | None,
    document_number: str | None,
    email: str | None,
    exclude_id: int | None = None,
) -> None:
    checks = []
    normalized_name = _normalize_text(name)
    document = _only_digits(document_number)
    normalized_email = _normalize_text(email)

    if document:
        checks.append(
            func.regexp_replace(func.coalesce(Company.document_number, ""), r"\D", "", "g")
            == document
        )
    if normalized_email:
        checks.append(func.lower(func.trim(Company.email)) == normalized_email)
    if normalized_name:
        checks.append(func.lower(func.trim(Company.name)) == normalized_name)
    if not checks:
        return

    expression = or_(*checks)
    if exclude_id is not None:
        expression = expression & (Company.id != exclude_id)
    existing = db.scalar(select(Company).where(expression).limit(1))
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Empresa ja cadastrada. Verifique nome, documento ou e-mail.",
        )


def _database_usage_mb(database_url: str) -> int | None:
    try:
        engine = create_engine(database_url, pool_pre_ping=True)
        with engine.connect() as connection:
            size_bytes = connection.execute(
                text("SELECT pg_database_size(current_database())")
            ).scalar()
        engine.dispose()
        return int(int(size_bytes or 0) / 1024 / 1024)
    except Exception:
        return None


def _apply_usage(company: Company) -> Company:
    settings = get_settings()
    limits = effective_plan_limits(company)
    company.database_usage_mb = _database_usage_mb(company.database_url)
    company.file_usage_mb = int(
        tenant_file_usage_bytes(company.code, UPLOAD_ROOT) / 1024 / 1024
    )
    company.database_limit_mb = int(limits["database_limit_mb"])
    company.file_limit_mb = int(limits["file_limit_mb"])
    company.xml_email_address = (
        f"xml+{company.code}-{company.xml_email_token}@{settings.xml_inbound_domain}"
        if company.xml_email_token
        else None
    )
    admin = _primary_admin_index(company.code)
    if admin is not None:
        company.admin_name = admin.name
        company.admin_email = admin.email
    return company


def _primary_admin_index(company_code: str) -> MasterUserIndex | None:
    normalized = normalize_company_code(company_code)
    with MasterSessionLocal() as db:
        admin = db.scalar(
            select(MasterUserIndex)
            .where(
                MasterUserIndex.company_code == normalized,
                MasterUserIndex.role == "admin",
            )
            .order_by(MasterUserIndex.id)
            .limit(1)
        )
        if admin is not None:
            return admin
        return db.scalar(
            select(MasterUserIndex)
            .where(MasterUserIndex.company_code == normalized)
            .order_by(MasterUserIndex.id)
            .limit(1)
        )


def _update_company_admin_login(
    company: Company,
    *,
    admin_name: str | None,
    admin_email: str | None,
    admin_password: str | None,
) -> None:
    if admin_name is None and admin_email is None and not admin_password:
        return
    current_admin = _primary_admin_index(company.code)
    current_email = current_admin.email if current_admin is not None else None
    current_user_id = current_admin.user_id if current_admin is not None else None
    next_name = (admin_name or current_admin.name if current_admin else admin_name) or "Administrador"
    next_email = (admin_email or current_email or "").strip().lower()
    if not next_email:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Informe o e-mail de login do cliente.",
        )

    tenant_engine = create_engine(company.database_url, pool_pre_ping=True)
    try:
        with tenant_engine.begin() as connection:
            user = None
            if current_user_id is not None:
                user = connection.execute(
                    text("SELECT id, email FROM users WHERE id = :id"),
                    {"id": current_user_id},
                ).mappings().first()
            if user is None and current_email:
                user = connection.execute(
                    text("SELECT id, email FROM users WHERE lower(email) = :email"),
                    {"email": current_email.strip().lower()},
                ).mappings().first()
            if user is None:
                user = connection.execute(
                    text(
                        """
                        SELECT id, email
                        FROM users
                        WHERE role = 'admin'
                        ORDER BY id
                        LIMIT 1
                        """
                    )
                ).mappings().first()
            if user is None:
                if not admin_password:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="Informe uma senha para criar o acesso admin do cliente.",
                    )
                inserted = connection.execute(
                    text(
                        """
                        INSERT INTO users (
                            name, email, password_hash, must_change_password, role, active
                        )
                        VALUES (
                            :name, :email, :password_hash, true, 'admin', true
                        )
                        RETURNING id
                        """
                    ),
                    {
                        "name": next_name.strip(),
                        "email": next_email,
                        "password_hash": hash_password(admin_password),
                    },
                ).mappings().first()
                user_id = int(inserted["id"])
                old_email = current_email
            else:
                old_email = str(user["email"])
                user_id = int(user["id"])
                existing_same_email = connection.execute(
                    text(
                        """
                        SELECT id
                        FROM users
                        WHERE lower(email) = :email
                          AND id <> :id
                        LIMIT 1
                        """
                    ),
                    {"email": next_email, "id": user_id},
                ).first()
                if existing_same_email is not None:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Outro usuario deste cliente ja usa este e-mail.",
                    )
                values = {
                    "id": user_id,
                    "name": next_name.strip(),
                    "email": next_email,
                    "password_hash": hash_password(admin_password) if admin_password else None,
                }
                connection.execute(
                    text(
                        """
                        UPDATE users
                        SET
                            name = :name,
                            email = :email,
                            password_hash = COALESCE(:password_hash, password_hash),
                            must_change_password = CASE
                                WHEN :password_hash IS NULL THEN must_change_password
                                ELSE true
                            END
                        WHERE id = :id
                        """
                    ),
                    values,
                )
    finally:
        tenant_engine.dispose()

    if old_email and old_email.strip().lower() != next_email:
        remove_user_index(company.code, old_email)
    upsert_user_index(
        company_code=company.code,
        company_name=company.name,
        user_id=user_id,
        name=next_name.strip(),
        email=next_email,
        role="admin",
        active=company.active,
    )


@router.get("/companies", response_model=list[CompanyRead])
def list_companies(_: dict = Depends(require_master_permission("master:companies"))) -> list[Company]:
    with MasterSessionLocal() as db:
        companies = list(db.scalars(select(Company).order_by(Company.name)).all())
        return [_apply_usage(company) for company in companies]


@router.get("/companies/contracts", response_model=list[CompanyContractRead])
def list_company_contracts(
    _: dict = Depends(require_master_permission("master:billing")),
) -> list[CompanyContractRead]:
    with MasterSessionLocal() as db:
        companies = list(
            db.scalars(
                select(Company).order_by(
                    Company.contract_expires_at.is_(None),
                    Company.contract_expires_at.asc(),
                    Company.name,
                )
            ).all()
        )
        return [_read_contract(company) for company in companies]


@router.get("/companies/cnpj-lookup/{cnpj}", response_model=CompanyTaxProfileLookup)
def lookup_company_cnpj(
    cnpj: str,
    _: dict = Depends(require_master_permission("master:companies")),
) -> dict:
    return lookup_company_tax_profile(cnpj).as_dict()


@router.post(
    "/companies/{company_id}/refresh-tax-profile",
    response_model=CompanyTaxProfileRefreshResult,
)
def refresh_company_tax_profile(
    company_id: int,
    _: dict = Depends(require_master_permission("master:companies")),
) -> CompanyTaxProfileRefreshResult:
    with MasterSessionLocal() as db:
        company = db.get(Company, company_id)
        if company is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Empresa nao encontrada.",
            )
        result = lookup_company_tax_profile(company.document_number)
        updated = apply_lookup_to_company(company, result)
        db.commit()
        db.refresh(company)
        try:
            sync_company_fiscal_seed(company)
        except Exception:
            pass
        return CompanyTaxProfileRefreshResult(
            company_id=company.id,
            code=company.code,
            name=company.name,
            document_number=company.document_number,
            updated=updated,
            status=result.status,
            message=result.message,
            tax_regime=company.tax_regime,
            crt=company.crt,
            source=result.source,
        )


@router.post(
    "/companies/tax-profiles/refresh-all",
    response_model=CompanyTaxProfileRefreshSummary,
)
def refresh_all_company_tax_profiles(
    _: dict = Depends(require_master_permission("master:companies")),
) -> CompanyTaxProfileRefreshSummary:
    results: list[CompanyTaxProfileRefreshResult] = []
    with MasterSessionLocal() as db:
        companies = list(db.scalars(select(Company).order_by(Company.name)).all())
        for company in companies:
            document = _only_digits(company.document_number)
            if company.person_type != "PJ" or not document or len(document) != 14:
                results.append(
                    CompanyTaxProfileRefreshResult(
                        company_id=company.id,
                        code=company.code,
                        name=company.name,
                        document_number=company.document_number,
                        updated=False,
                        status="skipped",
                        message="Sem CNPJ valido para consulta gratuita.",
                        tax_regime=company.tax_regime,
                        crt=company.crt,
                        source=company.tax_regime_source,
                    )
                )
                continue
            result = lookup_company_tax_profile(document)
            updated = apply_lookup_to_company(company, result)
            results.append(
                CompanyTaxProfileRefreshResult(
                    company_id=company.id,
                    code=company.code,
                    name=company.name,
                    document_number=company.document_number,
                    updated=updated,
                    status=result.status,
                    message=result.message,
                    tax_regime=company.tax_regime,
                    crt=company.crt,
                    source=result.source,
                )
            )
        db.commit()

    for item in results:
        if item.updated:
            with MasterSessionLocal() as db:
                company = db.get(Company, item.company_id)
                if company is not None:
                    try:
                        sync_company_fiscal_seed(company)
                    except Exception:
                        pass

    return CompanyTaxProfileRefreshSummary(
        total=len(results),
        updated=sum(1 for item in results if item.updated),
        skipped=sum(1 for item in results if item.status == "skipped"),
        failed=sum(1 for item in results if item.status not in {"found", "skipped"}),
        results=results,
    )


@router.post(
    "/companies",
    response_model=CompanyRead,
    status_code=status.HTTP_201_CREATED,
)
def create_company(
    company_in: CompanyCreate,
    _: dict = Depends(require_master_permission("master:companies")),
) -> Company:
    settings = get_settings()
    code = normalize_company_code(company_in.code)
    validate_company_code_for_domain(code)
    require_duplicate_authorization(
        str(company_in.admin_email),
        code,
        company_in.allow_cross_company_duplicate,
    )
    database_url = company_in.database_url or database_url_for_company(
        settings.database_url,
        code,
    )
    if company_in.provision_database:
        try:
            provision_tenant_database(
                database_url,
                admin_name=company_in.admin_name,
                admin_email=str(company_in.admin_email),
                admin_password=company_in.admin_password,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Nao foi possivel preparar o banco da empresa: {exc}",
            ) from exc

    with MasterSessionLocal() as db:
        existing = db.scalar(select(Company).where(Company.code == code))
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Ja existe uma empresa com este codigo.",
            )
        ensure_unique_company(
            db,
            name=company_in.name,
            document_number=company_in.document_number,
            email=str(company_in.email) if company_in.email else None,
        )
        validate_billing_fields(company_in.billing_day, company_in.payment_method)
        company = Company(
            code=code,
            name=company_in.name.strip(),
            business_type=company_in.business_type,
            person_type=company_in.person_type,
            document_number=company_in.document_number,
            state_registration=company_in.state_registration,
            municipal_registration=company_in.municipal_registration,
            trade_name=company_in.trade_name,
            contact_name=company_in.contact_name,
            responsible_cpf=_only_digits(company_in.responsible_cpf),
            responsible_birth_date=company_in.responsible_birth_date,
            phone=company_in.phone,
            email=str(company_in.email) if company_in.email else None,
            address_line=company_in.address_line,
            address_number=company_in.address_number,
            neighborhood=company_in.neighborhood,
            city=company_in.city,
            city_code=company_in.city_code,
            state=company_in.state,
            zip_code=company_in.zip_code,
            tax_regime=company_in.tax_regime,
            crt=company_in.crt,
            database_url=database_url,
            plan=normalize_plan_code(company_in.plan),
            plan_overrides=_clean_plan_overrides(company_in.plan_overrides),
            enabled_modules=modules_for_business_type(
                company_in.business_type,
                company_in.enabled_modules,
                normalize_plan_code(company_in.plan),
            ),
            monthly_price=company_in.monthly_price
            or plan_defaults(company_in.plan).monthly_price,
            billing_day=company_in.billing_day,
            payment_method=company_in.payment_method,
            contract_signed_at=company_in.contract_signed_at,
            contract_expires_at=_contract_expiration_for(
                company_in.contract_signed_at,
                company_in.contract_expires_at,
            ),
            contract_file_url=company_in.contract_file_url,
            contract_file_name=company_in.contract_file_name,
            contract_notes=company_in.contract_notes,
            digital_certificate_configured=company_in.digital_certificate_configured,
            digital_certificate_name=company_in.digital_certificate_name,
            digital_certificate_expires_at=company_in.digital_certificate_expires_at,
            digital_certificate_notes=company_in.digital_certificate_notes,
            xml_email_token=secrets.token_urlsafe(6).lower().replace("_", "").replace("-", ""),
            xml_email_enabled=company_in.xml_email_enabled,
            status=company_in.status,
            active=company_in.active,
            notes=company_in.notes,
        )
        db.add(company)
        _complete_company_city_code(company)
        db.commit()
        db.refresh(company)
        if company_in.provision_database:
            sync_company_fiscal_seed(company)
        upsert_user_index(
            company_code=company.code,
            company_name=company.name,
            user_id=None,
            name=company_in.admin_name.strip(),
            email=str(company_in.admin_email),
            role="admin",
            active=company.active,
        )
        return _apply_usage(company)


@router.put("/companies/{company_id}", response_model=CompanyRead)
def update_company(
    company_id: int,
    company_in: CompanyUpdate,
    _: dict = Depends(require_master_permission("master:companies")),
) -> Company:
    with MasterSessionLocal() as db:
        company = db.get(Company, company_id)
        if company is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Empresa nao encontrada.",
            )
        data = company_in.model_dump(exclude_unset=True)
        admin_name = data.pop("admin_name", None)
        admin_email_value = data.pop("admin_email", None)
        admin_email = str(admin_email_value) if admin_email_value else None
        admin_password = data.pop("admin_password", None)
        allow_cross_company_duplicate = bool(
            data.pop("allow_cross_company_duplicate", False)
        )
        if "responsible_cpf" in data:
            data["responsible_cpf"] = _only_digits(data["responsible_cpf"])
        if admin_email:
            require_duplicate_authorization(
                admin_email,
                company.code,
                allow_cross_company_duplicate,
            )
        ensure_unique_company(
            db,
            name=data.get("name", company.name),
            document_number=data.get("document_number", company.document_number),
            email=(
                str(data["email"])
                if data.get("email") is not None
                else company.email
            ),
            exclude_id=company_id,
        )
        if "business_type" in data or "enabled_modules" in data:
            business_type = data.get("business_type", company.business_type)
            modules = data.get("enabled_modules", company.enabled_modules)
        if "plan" in data and data["plan"] is not None:
            data["plan"] = normalize_plan_code(data["plan"])
            if "monthly_price" in data and not data.get("monthly_price"):
                data["monthly_price"] = plan_defaults(data["plan"]).monthly_price
        if "business_type" in data or "enabled_modules" in data or "plan" in data:
            business_type = data.get("business_type", company.business_type)
            modules = data.get("enabled_modules", company.enabled_modules)
            plan_code = normalize_plan_code(data.get("plan", company.plan))
            data["enabled_modules"] = modules_for_business_type(
                business_type,
                modules,
                plan_code,
            )
        if "plan_overrides" in data:
            data["plan_overrides"] = _clean_plan_overrides(data["plan_overrides"])
        if "contract_signed_at" in data or "contract_expires_at" in data:
            expires_input = (
                data["contract_expires_at"]
                if "contract_expires_at" in data
                else None
                if "contract_signed_at" in data
                else company.contract_expires_at
            )
            data["contract_expires_at"] = _contract_expiration_for(
                data.get("contract_signed_at", company.contract_signed_at),
                expires_input,
            )
        validate_billing_fields(
            data.get("billing_day", company.billing_day),
            data.get("payment_method", company.payment_method),
        )
        for field, value in data.items():
            if value is None and field not in {"notes", "plan_overrides"}:
                continue
            if field == "name":
                value = value.strip()
            if field == "email" and value is not None:
                value = str(value)
            setattr(company, field, value)
        _complete_company_city_code(company)
        db.commit()
        db.refresh(company)
        try:
            sync_company_fiscal_seed(company)
        except Exception:
            pass
        _update_company_admin_login(
            company,
            admin_name=admin_name,
            admin_email=admin_email,
            admin_password=admin_password,
        )
        return _apply_usage(company)

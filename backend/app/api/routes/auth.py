from datetime import UTC, datetime, timedelta
import secrets

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, get_current_user
from app.core.database import get_db
from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.core.security import (
    create_access_token,
    decode_access_token,
    decode_access_token_unverified_exp,
    hash_password,
    verify_password,
)
from app.models.master_user import MasterUser
from app.models.company import Company
from app.models.pdv_terminal import PdvTerminal
from app.models.user import User
from app.schemas.auth import (
    AutomaticLoginRequest,
    ChangePasswordRequest,
    ChangePasswordResponse,
    CurrentUserRead,
    LoginRequest,
    TokenResponse,
)
from app.schemas.pdv_terminal import PdvTerminalActivationRequest
from app.services.access_control import get_user_permission_codes
from app.services.company_modules import modules_for_business_type, segment_operational_roles
from app.services.company_presence import touch_company_presence
from app.services.master_permissions import get_master_user_permission_codes
from app.services.master_user_index import find_user_companies, redirect_detail_for_email
from app.services.tenancy import (
    get_company_by_code,
    get_enabled_modules_for_company,
    normalize_company_code,
    require_active_company,
    session_for_company,
)

router = APIRouter()

PDV_ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 180
PDV_REFRESH_MAX_AGE_DAYS = 365
PDV_TERMINAL_USER_EMAIL = "_pdv_terminal@lyncar.local"


def _is_pdv_client_type(value: str | None) -> bool:
    normalized = (value or "").strip().lower().replace("-", "_")
    return normalized in {"pdv", "pdv_windows", "windows_pdv", "pdv_desktop"}


def _ensure_pdv_windows_enabled(company_code: str) -> None:
    if "pdv_windows" not in get_enabled_modules_for_company(company_code):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="PDV Windows nao liberado para esta empresa. Procure a Lyncar.",
        )


def _ensure_company_active(company_code: str) -> None:
    try:
        require_active_company(company_code)
    except LookupError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Empresa bloqueada ou inativa. Procure a Lyncar.",
        ) from exc


def _validate_company_code(company_code: str) -> tuple[str, str]:
    settings = get_settings()
    normalized = normalize_company_code(company_code)
    if normalized == normalize_company_code(settings.master_company_code):
        return settings.master_company_code, settings.master_company_name
    try:
        company = require_active_company(company_code)
    except LookupError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empresa nao encontrada ou inativa.",
        ) from exc
    return normalize_company_code(company.code), company.name


def _token_response_for_tenant_user(
    company_code: str,
    user: User,
    *,
    client_type: str | None = None,
) -> TokenResponse:
    _ensure_company_active(company_code)
    company = get_company_by_code(company_code)
    company_name = company.name if company else company_code
    plan_code = (company.plan or "start") if company else "start"
    enabled_modules = modules_for_business_type(
        company.business_type if company else "custom",
        company.enabled_modules if company else None,
        plan_code,
    )
    operational_roles = segment_operational_roles(
        company.business_type if company else "custom"
    )
    if _is_pdv_client_type(client_type) and "pdv_windows" not in enabled_modules:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="PDV Windows nao liberado para esta empresa. Procure a Lyncar.",
        )
    with session_for_company(company_code) as db:
        current = db.get(User, user.id)
        if current is None or not current.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario inativo ou nao encontrado.",
            )
        permissions = sorted(get_user_permission_codes(db, current, enabled_modules))
        token = create_access_token(
            subject=str(current.id),
            extra_claims={
                "role": current.role,
                "permissions": permissions,
                "company_code": normalize_company_code(company_code),
                "company_name": company_name,
                "plan_code": plan_code,
                "client_type": client_type or "web",
            },
            expires_minutes=PDV_ACCESS_TOKEN_EXPIRE_MINUTES
            if _is_pdv_client_type(client_type)
            else None,
        )
        return TokenResponse(
            access_token=token,
            company_code=normalize_company_code(company_code),
            company_name=company_name,
            business_type=company.business_type if company else "custom",
            plan_code=plan_code,
            enabled_modules=enabled_modules,
            seller_role_enabled=operational_roles["seller"],
            technician_role_enabled=operational_roles["technician"],
            permissions=permissions,
            must_change_password=bool(current.must_change_password),
        )


def _token_response_for_master_user(user: MasterUser) -> TokenResponse:
    settings = get_settings()
    with MasterSessionLocal() as db:
        current = db.get(MasterUser, user.id)
        if current is None or not current.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario master inativo ou nao encontrado.",
            )
        permissions = get_master_user_permission_codes(db, current)
        role = "superadmin" if "master:manage" in permissions else "master_staff"
    token = create_access_token(
        subject=f"master:{user.id}",
        extra_claims={
            "role": role,
            "permissions": permissions,
            "company_code": settings.master_company_code,
            "company_name": settings.master_company_name,
            "scope": "master",
        },
    )
    return TokenResponse(
        access_token=token,
        company_code=settings.master_company_code,
        company_name=settings.master_company_name,
        business_type="master",
        plan_code="enterprise",
        enabled_modules=["master"],
        seller_role_enabled=True,
        technician_role_enabled=True,
        permissions=permissions,
        must_change_password=bool(user.must_change_password),
    )


def _terminal_user(db: Session) -> User:
    user = db.scalar(select(User).where(User.email == PDV_TERMINAL_USER_EMAIL))
    if user is None:
        user = User(
            name="Terminal PDV Lyncar",
            email=PDV_TERMINAL_USER_EMAIL,
            password_hash=hash_password(secrets.token_urlsafe(32)),
            role="admin",
            active=True,
            must_change_password=False,
            password_changed_at=datetime.now(UTC),
        )
        db.add(user)
        db.flush()
    else:
        user.active = True
        user.role = "admin"
        user.must_change_password = False
    return user


@router.post("/pdv/activate-terminal")
def activate_pdv_terminal(payload: PdvTerminalActivationRequest) -> dict:
    code = payload.activation_code.strip().upper()
    now = datetime.now(UTC)
    with MasterSessionLocal() as master_db:
        companies = list(
            master_db.scalars(
                select(Company).where(
                    Company.active.is_(True),
                    Company.status == "active",
                )
            ).all()
        )
    for company in companies:
        company_code = normalize_company_code(company.code)
        if "pdv_windows" not in get_enabled_modules_for_company(company_code):
            continue
        with session_for_company(company_code) as db:
            terminals = list(
                db.scalars(
                    select(PdvTerminal).where(
                        PdvTerminal.activation_code_hash.is_not(None),
                        PdvTerminal.activation_code_expires_at.is_not(None),
                        PdvTerminal.activation_code_expires_at >= now,
                    )
                ).all()
            )
            for terminal in terminals:
                if not terminal.activation_code_hash:
                    continue
                if not verify_password(code, terminal.activation_code_hash):
                    continue
                user = _terminal_user(db)
                terminal_key = secrets.token_urlsafe(32)
                while db.scalar(
                    select(PdvTerminal.id).where(
                        PdvTerminal.terminal_key == terminal_key
                    )
                ) is not None:
                    terminal_key = secrets.token_urlsafe(32)
                terminal.terminal_key = terminal_key
                terminal.app_version = payload.app_version
                terminal.device_label = payload.device_label or terminal.device_label
                terminal.machine_name = payload.machine_name
                terminal.windows_user = payload.windows_user
                terminal.windows_version = payload.windows_version
                terminal.device_fingerprint = payload.device_fingerprint
                terminal.activation_status = "active"
                terminal.activation_code_hash = None
                terminal.activation_code_expires_at = None
                terminal.activated_at = now
                terminal.active = True
                terminal.current_status = "closed"
                terminal.updated_at = now
                terminal.last_seen_at = now
                terminal_payload = {
                    "id": terminal.id,
                    "cash_register_number": terminal.cash_register_number,
                    "terminal_key": terminal.terminal_key,
                    "app_version": terminal.app_version,
                    "device_label": terminal.device_label,
                    "active": terminal.active,
                    "activation_status": terminal.activation_status,
                    "activation_code_expires_at": terminal.activation_code_expires_at,
                    "activated_at": terminal.activated_at,
                    "machine_name": terminal.machine_name,
                    "windows_user": terminal.windows_user,
                    "windows_version": terminal.windows_version,
                    "device_fingerprint": terminal.device_fingerprint,
                    "current_status": terminal.current_status,
                    "current_operator_name": terminal.current_operator_name,
                    "cash_opened_at": terminal.cash_opened_at,
                    "current_session_total_amount": terminal.current_session_total_amount,
                    "today_sales_count": 0,
                    "today_sales_amount": 0,
                    "created_at": terminal.created_at,
                    "updated_at": terminal.updated_at,
                    "last_seen_at": terminal.last_seen_at,
                }
                db.commit()
                db.refresh(user)
                response = _token_response_for_tenant_user(
                    company_code,
                    user,
                    client_type="pdv_windows",
                ).model_dump(mode="json")
                response["pdv_terminal"] = terminal_payload
                return response
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Codigo de ativacao invalido ou expirado.",
    )


@router.post("/login", response_model=TokenResponse)
def login(login_in: LoginRequest) -> TokenResponse:
    company_code, company_name = _validate_company_code(login_in.company_code)
    settings = get_settings()
    if company_code == settings.master_company_code:
        with MasterSessionLocal() as db:
            user = db.scalar(
                select(MasterUser).where(MasterUser.email == login_in.email.lower())
            )
            if user is None or not user.active:
                redirect_detail = redirect_detail_for_email(str(login_in.email))
                if redirect_detail is not None:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=redirect_detail,
                    )
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="E-mail ou senha invalidos.",
                )
            if not verify_password(login_in.password, user.password_hash):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="E-mail ou senha invalidos.",
                )
            return _token_response_for_master_user(user)

    company = get_company_by_code(company_code)
    plan_code = (company.plan or "start") if company else "start"
    enabled_modules = modules_for_business_type(
        company.business_type if company else "custom",
        company.enabled_modules if company else None,
        plan_code,
    )
    operational_roles = segment_operational_roles(
        company.business_type if company else "custom"
    )
    with session_for_company(company_code) as db:
        user = db.scalar(select(User).where(User.email == login_in.email.lower()))
        if user is None or not user.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="E-mail ou senha invalidos.",
            )

        if not verify_password(login_in.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="E-mail ou senha invalidos.",
            )

        permissions = sorted(get_user_permission_codes(db, user, enabled_modules))
        user_id = user.id
        user_role = user.role
        must_change_password = bool(user.must_change_password)
    token = create_access_token(
        subject=str(user_id),
        extra_claims={
            "role": user_role,
            "permissions": permissions,
            "company_code": company_code,
            "company_name": company_name,
            "plan_code": plan_code,
        },
    )
    return TokenResponse(
        access_token=token,
        company_code=company_code,
        company_name=company_name,
        business_type=company.business_type if company else "custom",
        plan_code=plan_code,
        enabled_modules=enabled_modules,
        seller_role_enabled=operational_roles["seller"],
        technician_role_enabled=operational_roles["technician"],
        permissions=permissions,
        must_change_password=must_change_password,
    )


@router.post("/change-password", response_model=ChangePasswordResponse)
def change_password(
    payload: ChangePasswordRequest,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> ChangePasswordResponse:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
        )
    try:
        token_data = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        ) from exc

    if payload.current_password == payload.new_password:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A nova senha deve ser diferente da senha provisoria.",
        )

    subject = str(token_data.get("sub") or "")
    if token_data.get("scope") == "master" or subject.startswith("master:"):
        master_id = int(subject.split(":", 1)[1])
        with MasterSessionLocal() as db:
            user = db.get(MasterUser, master_id)
            if user is None or not user.active:
                raise HTTPException(status_code=401, detail="Usuario invalido.")
            if not verify_password(payload.current_password, user.password_hash):
                raise HTTPException(status_code=401, detail="Senha atual invalida.")
            user.password_hash = hash_password(payload.new_password)
            user.must_change_password = False
            user.password_changed_at = datetime.now(UTC)
            db.commit()
        return ChangePasswordResponse()

    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    _ensure_company_active(company_code)
    user_id = int(subject)
    with session_for_company(company_code) as db:
        user = db.get(User, user_id)
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="Usuario invalido.")
        if not verify_password(payload.current_password, user.password_hash):
            raise HTTPException(status_code=401, detail="Senha atual invalida.")
        user.password_hash = hash_password(payload.new_password)
        user.must_change_password = False
        user.password_changed_at = datetime.now(UTC)
        db.commit()
    return ChangePasswordResponse()


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> TokenResponse:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
        )
    try:
        payload = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        ) from exc

    settings = get_settings()
    company_code = normalize_company_code(
        str(payload.get("company_code") or settings.default_company_code)
    )
    subject = str(payload.get("sub") or "")
    if payload.get("scope") == "master" or subject.startswith("master:"):
        master_id_text = subject.split(":", 1)[1] if ":" in subject else ""
        master_id = int(master_id_text)
        with MasterSessionLocal() as db:
            user = db.get(MasterUser, master_id)
            if user is None or not user.active:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Usuario inativo ou nao encontrado.",
                )
            return _token_response_for_master_user(user)

    user_id = int(subject)
    _ensure_company_active(company_code)
    with session_for_company(company_code) as db:
        user = db.get(User, user_id)
        if user is None or not user.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario inativo ou nao encontrado.",
            )
        return _token_response_for_tenant_user(
            company_code,
            user,
            client_type=str(payload.get("client_type") or "web"),
        )


@router.post("/pdv/refresh", response_model=TokenResponse)
def refresh_pdv_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> TokenResponse:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessao do PDV ausente. Entre novamente.",
        )
    try:
        payload = decode_access_token_unverified_exp(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessao do PDV invalida. Entre novamente.",
        ) from exc

    if not _is_pdv_client_type(str(payload.get("client_type") or "")):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessao nao pertence ao PDV Windows.",
        )
    if payload.get("scope") == "master":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="PDV nao pode usar sessao master.",
        )
    issued_at = payload.get("iat")
    if isinstance(issued_at, (int, float)):
        issued_datetime = datetime.fromtimestamp(float(issued_at), tz=UTC)
        if datetime.now(UTC) - issued_datetime > timedelta(days=PDV_REFRESH_MAX_AGE_DAYS):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sessao do PDV antiga demais. Entre novamente.",
            )

    company_code = normalize_company_code(str(payload.get("company_code") or ""))
    if not company_code:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empresa da sessao do PDV nao identificada.",
        )
    _ensure_company_active(company_code)
    _ensure_pdv_windows_enabled(company_code)

    try:
        user_id = int(str(payload.get("sub") or ""))
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario da sessao do PDV invalido.",
        ) from exc
    with session_for_company(company_code) as db:
        user = db.get(User, user_id)
        if user is None or not user.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario inativo ou nao encontrado.",
            )
        response = _token_response_for_tenant_user(
            company_code,
            user,
            client_type="pdv_windows",
        )
        if "sales:create" not in response.permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem acesso ao PDV.",
            )
        return response


@router.post("/login/automatic", response_model=TokenResponse)
def automatic_login(login_in: AutomaticLoginRequest) -> TokenResponse:
    matches = [
        match
        for match in find_user_companies(str(login_in.email))
        if match.active
    ]
    if len(matches) != 1:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="E-mail ou senha invalidos.",
        )
    response = login(
        LoginRequest(
            company_code=matches[0].company_code,
            email=login_in.email,
            password=login_in.password,
        )
    )
    if (login_in.client_type or "").strip().lower() == "mobile":
        if "app:access" not in response.permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem acesso ao aplicativo movel.",
            )
    if _is_pdv_client_type(login_in.client_type):
        payload = decode_access_token(response.access_token)
        user_id = int(str(payload.get("sub") or "0"))
        with session_for_company(response.company_code) as db:
            user = db.get(User, user_id)
            if user is None or not user.active:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Usuario inativo ou nao encontrado.",
                )
            response = _token_response_for_tenant_user(
                response.company_code,
                user,
                client_type="pdv_windows",
            )
        if "sales:create" not in response.permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem acesso ao PDV.",
            )
    return response


@router.post("/heartbeat")
def heartbeat(
    client_type: str = Query(default="web", max_length=30),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    current_user: User = Depends(get_current_user),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
        )
    try:
        token_data = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        ) from exc
    company_code = normalize_company_code(str(token_data.get("company_code") or ""))
    if company_code and company_code != get_settings().master_company_code:
        touch_company_presence(
            company_code=company_code,
            user=current_user,
            client_type=client_type.strip() or "web",
        )
    return {"ok": True}


@router.get("/me", response_model=CurrentUserRead)
def read_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> CurrentUserRead:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
        )
    try:
        payload = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        ) from exc
    settings = get_settings()
    subject = str(payload.get("sub") or "")
    company_code = normalize_company_code(
        str(payload.get("company_code") or settings.master_company_code)
    )
    company_name = str(payload.get("company_name") or settings.master_company_name)
    if payload.get("scope") == "master" or subject.startswith("master:"):
        try:
            master_id = int(subject.split(":", 1)[1])
        except (IndexError, ValueError) as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token master invalido.",
            ) from exc
        with MasterSessionLocal() as master_db:
            user = master_db.get(MasterUser, master_id)
            if user is None or not user.active:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Usuario master inativo ou nao encontrado.",
                )
            return CurrentUserRead(
                id=user.id,
                name=user.name,
                email=user.email,
                role="superadmin"
                if "master:manage" in get_master_user_permission_codes(master_db, user)
                else "master_staff",
                company_code=settings.master_company_code,
                company_name=settings.master_company_name,
                business_type="master",
                plan_code="enterprise",
                enabled_modules=["master"],
                permissions=get_master_user_permission_codes(master_db, user),
            )

    company = get_company_by_code(company_code)
    _ensure_company_active(company_code)
    plan_code = company.plan if company else "start"
    enabled_modules = modules_for_business_type(
        company.business_type if company else "custom",
        company.enabled_modules if company else None,
        plan_code,
    )
    try:
        user_id = int(subject)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido.",
        ) from exc
    with session_for_company(company_code) as db:
        current_user = db.get(User, user_id)
        if current_user is None or not current_user.active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario inativo ou nao encontrado.",
            )
        return CurrentUserRead(
            id=current_user.id,
            name=current_user.name,
            email=current_user.email,
            role=current_user.role,
            company_code=company_code,
            company_name=company_name,
            business_type=company.business_type if company else "custom",
            plan_code=plan_code,
            enabled_modules=enabled_modules,
            permissions=sorted(
                get_user_permission_codes(db, current_user, enabled_modules)
            ),
        )

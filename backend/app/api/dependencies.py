from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials
from jwt import ExpiredSignatureError, InvalidTokenError
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.errors import api_error
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.master_user import MasterUser
from app.models.user import User
from app.services.access_control import user_has_permission
from app.services.company_modules import permission_allowed_by_modules
from app.services.master_permissions import master_user_has_permission
from app.services.plan_limits import enforce_database_limit
from app.services.tenancy import (
    company_code_from_token_claims,
    get_enabled_modules_for_company,
)
from app.services.web_sessions import has_session_cookie, internal_access_token, session_from_request


class CookieAwareBearer:
    """Keep existing route dependencies while accepting the HttpOnly web session."""

    def __call__(self, request: Request) -> HTTPAuthorizationCredentials | None:
        authorization = request.headers.get("Authorization", "")
        if authorization.lower().startswith("bearer "):
            return HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=authorization.split(" ", 1)[1].strip()
            )
        if has_session_cookie(request):
            try:
                row = session_from_request(request)
            except HTTPException:
                return None
            return HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=internal_access_token(row)
            )
        return None


bearer_scheme = CookieAwareBearer()
PDV_CLIENT_TYPES = {"pdv", "pdv_windows", "windows_pdv", "pdv_desktop"}


def _is_pdv_client_type(value: object) -> bool:
    normalized = str(value or "").strip().lower().replace("-", "_")
    return normalized in PDV_CLIENT_TYPES


def _ensure_company_access(payload: dict | None) -> list[str] | None:
    if payload is None or payload.get("scope") == "master":
        return None
    try:
        company_code = company_code_from_token_claims(payload)
    except LookupError as exc:
        raise api_error(
            status.HTTP_403_FORBIDDEN,
            "TENANT_CONTEXT_INVALID",
            "Nao foi possivel validar a empresa desta sessao. Entre novamente.",
        ) from exc
    enabled_modules = get_enabled_modules_for_company(company_code)
    if (
        _is_pdv_client_type(payload.get("client_type"))
        and "pdv_windows" not in enabled_modules
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="PDV Windows nao liberado para esta empresa. Procure a Lyncar.",
        )
    return enabled_modules


def _decode_credentials_or_401(
    credentials: HTTPAuthorizationCredentials | None,
) -> dict | None:
    if credentials is None:
        return None
    try:
        return decode_access_token(credentials.credentials)
    except ExpiredSignatureError as exc:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "SESSION_EXPIRED",
            "Sua sessao expirou. Entre novamente.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except InvalidTokenError as exc:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "TOKEN_INVALID",
            "Sua sessao nao e valida. Entre novamente.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = decode_access_token(credentials.credentials)
        user_id = int(payload["sub"])
        _ensure_company_access(payload)
    except ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expirado.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except (InvalidTokenError, KeyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user = db.get(User, user_id)
    if user is None or not user.active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario inativo ou nao encontrado.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token_email = payload.get("user_email")
    if isinstance(token_email, str) and user.email.lower() != token_email.lower():
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "TENANT_ACCESS_REVOKED",
            "A sessao nao corresponde ao usuario desta empresa. Entre novamente.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acesso permitido apenas para administradores.",
        )
    return current_user


def require_superadmin(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = decode_access_token(credentials.credentials)
    except (ExpiredSignatureError, InvalidTokenError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    if payload.get("scope") != "master" or payload.get("role") != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acesso permitido apenas para superadmin master.",
        )
    return payload


def require_master_permission(permission_code: str):
    def dependency(
        credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    ) -> dict:
        if credentials is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de acesso ausente.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        try:
            payload = decode_access_token(credentials.credentials)
        except (ExpiredSignatureError, InvalidTokenError) as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token invalido ou expirado.",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc
        subject = str(payload.get("sub") or "")
        if payload.get("scope") != "master" or not subject.startswith("master:"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Acesso permitido apenas para usuarios master.",
            )
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
            if not master_user_has_permission(master_db, user, permission_code):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Usuario master sem permissao para esta acao.",
                )
        return payload

    return dependency


def require_permission(permission_code: str):
    def dependency(
        request: Request,
        current_user: User = Depends(get_current_user),
        credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
        db: Session = Depends(get_db),
    ) -> User:
        if not user_has_permission(db, current_user, permission_code):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem permissao para esta acao.",
            )
        payload = _decode_credentials_or_401(credentials)
        if payload is not None and payload.get("scope") != "master":
            company_code = company_code_from_token_claims(payload)
            enabled_modules = _ensure_company_access(payload) or []
            if not permission_allowed_by_modules(permission_code, enabled_modules):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Modulo nao contratado para esta empresa.",
                )
            if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
                enforce_database_limit(db, company_code)
        return current_user

    return dependency


def require_any_permission(*permission_codes: str):
    def dependency(
        request: Request,
        current_user: User = Depends(get_current_user),
        credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
        db: Session = Depends(get_db),
    ) -> User:
        allowed_codes = set(permission_codes)
        payload = _decode_credentials_or_401(credentials)
        if payload is not None and payload.get("scope") != "master":
            company_code = company_code_from_token_claims(payload)
            enabled_modules = _ensure_company_access(payload) or []
            allowed_codes = {
                code
                for code in allowed_codes
                if permission_allowed_by_modules(code, enabled_modules)
            }
            if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
                enforce_database_limit(db, company_code)
        if not any(
            user_has_permission(db, current_user, permission_code)
            for permission_code in allowed_codes
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Usuario sem permissao para esta acao.",
            )
        return current_user

    return dependency

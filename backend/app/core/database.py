from collections.abc import Generator

from fastapi import HTTPException, Request, status
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings
from jwt import ExpiredSignatureError, InvalidTokenError

from app.core.errors import api_error
from app.core.security import decode_access_token
from app.services.tenancy import (
    company_code_from_token_claims,
    normalize_company_code,
    session_for_company,
)
from app.services.web_sessions import session_from_request

settings = get_settings()

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


class Base(DeclarativeBase):
    pass


def _company_code_from_request(request: Request) -> str:
    authorization = request.headers.get("Authorization", "")
    if authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        try:
            payload = decode_access_token(token)
            if payload.get("scope") == "master":
                return normalize_company_code(settings.default_company_code)
            return company_code_from_token_claims(payload)
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
        except LookupError as exc:
            raise api_error(
                status.HTTP_403_FORBIDDEN,
                "TENANT_CONTEXT_INVALID",
                "Nao foi possivel validar a empresa desta sessao. Entre novamente.",
            ) from exc
    if request.cookies.get("lyncar_session"):
        row = session_from_request(request)
        if row.claims.get("scope") == "master":
            return normalize_company_code(settings.default_company_code)
        return normalize_company_code(row.company_code)
    return normalize_company_code(settings.default_company_code)


def get_db(request: Request) -> Generator[Session, None, None]:
    try:
        db = session_for_company(_company_code_from_request(request))
    except LookupError as exc:
        raise api_error(
            status.HTTP_403_FORBIDDEN,
            "COMPANY_BLOCKED",
            "A empresa esta bloqueada ou inativa. Procure a Lyncar.",
        ) from exc
    try:
        yield db
    finally:
        db.close()

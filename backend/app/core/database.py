from collections.abc import Generator

from fastapi import HTTPException, Request, status
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings
from app.core.security import decode_access_token
from app.services.tenancy import normalize_company_code, session_for_company

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
            company_code = payload.get("company_code")
            if isinstance(company_code, str) and company_code.strip():
                if payload.get("scope") == "master":
                    return normalize_company_code(settings.default_company_code)
                return normalize_company_code(company_code)
        except Exception:
            return normalize_company_code(settings.default_company_code)
    return normalize_company_code(settings.default_company_code)


def get_db(request: Request) -> Generator[Session, None, None]:
    try:
        db = session_for_company(_company_code_from_request(request))
    except LookupError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Empresa bloqueada ou inativa. Procure a Lyncar.",
        ) from exc
    try:
        yield db
    finally:
        db.close()

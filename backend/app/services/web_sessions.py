from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib
import secrets

from fastapi import HTTPException, Request, Response, status
from sqlalchemy import select

from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.core.security import create_access_token, decode_access_token
from app.models.auth_session import AuthSession, SecurityAuditLog
from app.services.tenancy import require_active_company_by_id

SESSION_COOKIE = "lyncar_session"
CSRF_COOKIE = "lyncar_csrf"
REFRESH_DAYS = 30
IDLE_TIMEOUT = timedelta(hours=3)


def _request_counts_as_activity(request: Request) -> bool:
    """Exclude background presence/session maintenance from idle activity."""
    path = request.url.path.rstrip("/")
    return path not in {
        "/auth/heartbeat",
        "/auth/web/session",
        "/auth/web/refresh",
        "/auth/web/logout",
    }


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _cookie_options() -> dict:
    settings = get_settings()
    return {
        "httponly": False,
        "secure": settings.app_env.lower() in {"production", "prod"},
        "samesite": "lax",
        "path": "/",
    }


def _set_cookies(response: Response, session_token: str, csrf_token: str) -> None:
    options = _cookie_options()
    response.set_cookie(SESSION_COOKIE, session_token, httponly=True, **{k: v for k, v in options.items() if k != "httponly"})
    response.set_cookie(CSRF_COOKIE, csrf_token, **options)
    # The token is intentionally not secret; it is the readable half of the
    # double-submit CSRF protection and is needed by a frontend on another
    # subdomain to send X-CSRF-Token.
    response.headers["X-CSRF-Token"] = csrf_token


def _clear_cookies(response: Response) -> None:
    response.delete_cookie(SESSION_COOKIE, path="/")
    response.delete_cookie(CSRF_COOKIE, path="/")


def _audit(db, event: str, request: Request, session: AuthSession | None, outcome: str = "success", metadata: dict | None = None) -> None:
    db.add(
        SecurityAuditLog(
            event=event,
            outcome=outcome,
            user_subject=session.user_subject if session else None,
            company_id=session.company_id if session else None,
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent"),
            metadata_json=metadata,
        )
    )


def _validate_row(db, row: AuthSession | None, request: Request, refresh: bool = False) -> AuthSession:
    now = datetime.now(UTC)
    if row is not None and row.revoked_at is not None:
        _audit(db, "session_replay_detected", request, row, "failure")
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_REVOKED", "message": "Esta sessao foi encerrada. Entre novamente."})
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_INVALID", "message": "Sua sessao nao e valida. Entre novamente."})
    if row.last_seen_at is not None and now - row.last_seen_at > IDLE_TIMEOUT:
        row.revoked_at = now
        _audit(db, "session_idle_timeout", request, row, "failure")
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_IDLE_TIMEOUT", "message": "Sua sessao expirou por inatividade. Entre novamente."})
    deadline = row.refresh_expires_at if refresh else row.expires_at
    if deadline is not None and deadline <= now:
        _audit(db, "session_expired", request, row, "failure")
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_EXPIRED", "message": "Sua sessao expirou. Entre novamente."})
    if row.company_id is not None:
        try:
            require_active_company_by_id(row.company_id)
        except LookupError as exc:
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail={"code": "COMPANY_BLOCKED", "message": "A empresa esta bloqueada ou inativa. Procure a Lyncar."}) from exc
    if _request_counts_as_activity(request):
        row.last_seen_at = now
    return row


def session_from_request(request: Request, refresh: bool = False) -> AuthSession:
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_REQUIRED", "message": "Sessao ausente. Entre novamente."})
    with MasterSessionLocal() as db:
        row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(token)))
        row = _validate_row(db, row, request, refresh)
        db.flush()
        # Keep the validated values available after the master session closes.
        db.expunge(row)
        db.commit()
        return row


def csrf_from_request(request: Request) -> None:
    cookie = request.cookies.get(CSRF_COOKIE)
    header = request.headers.get("X-CSRF-Token")
    if not cookie or not header or not secrets.compare_digest(cookie, header):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail={"code": "CSRF_INVALID", "message": "A validacao de seguranca falhou. Atualize a pagina e tente novamente."})
    with MasterSessionLocal() as db:
        row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(request.cookies.get(SESSION_COOKIE, ""))))
        if row is None or not secrets.compare_digest(row.csrf_hash, _hash(cookie)):
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail={"code": "CSRF_INVALID", "message": "A validacao de seguranca falhou. Atualize a pagina e tente novamente."})


def refresh_csrf_cookie(request: Request, response: Response) -> None:
    """Re-issue the readable CSRF token when a browser restores its session.

    The HttpOnly session cookie survives a page reload, while the Flutter web
    client intentionally keeps the CSRF value only in memory. Returning a new
    token from the session bootstrap keeps the double-submit check usable
    without exposing the session cookie.
    """
    session_token = request.cookies.get(SESSION_COOKIE)
    if not session_token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_REQUIRED", "message": "Sessao ausente. Entre novamente."})
    csrf_token = secrets.token_urlsafe(32)
    with MasterSessionLocal() as db:
        row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(session_token)))
        _validate_row(db, row, request)
        row.csrf_hash = _hash(csrf_token)
        db.commit()
    _set_cookies(response, session_token, csrf_token)


def _create_row(
    access_token: str,
    request: Request,
    refresh_expires_at: datetime | None = None,
    last_seen_at: datetime | None = None,
) -> tuple[AuthSession, str, str]:
    payload = decode_access_token(access_token)
    session_token = secrets.token_urlsafe(48)
    csrf_token = secrets.token_urlsafe(32)
    now = datetime.now(UTC)
    expires_at = datetime.fromtimestamp(float(payload["exp"]), tz=UTC)
    claims = {key: value for key, value in payload.items() if key not in {"exp", "iat", "jti"}}
    company_id = payload.get("company_id")
    row = AuthSession(
        token_hash=_hash(session_token),
        csrf_hash=_hash(csrf_token),
        user_subject=str(payload.get("sub") or ""),
        company_id=int(company_id) if company_id is not None else None,
        company_code=str(payload.get("company_code") or ""),
        claims=claims,
        expires_at=expires_at,
        refresh_expires_at=refresh_expires_at or now + timedelta(days=REFRESH_DAYS),
        last_seen_at=last_seen_at or now,
        user_agent=request.headers.get("user-agent"),
        ip_address=request.client.host if request.client else None,
    )
    return row, session_token, csrf_token


def create_session(access_token: str, request: Request, response: Response) -> AuthSession:
    row, session_token, csrf_token = _create_row(access_token, request)
    with MasterSessionLocal() as db:
        db.add(row)
        _audit(db, "session_created", request, row)
        db.commit()
        db.refresh(row)
        _set_cookies(response, session_token, csrf_token)
        return row


def internal_access_token(row: AuthSession) -> str:
    return create_access_token(row.user_subject, extra_claims=dict(row.claims))


def rotate_session(request: Request, response: Response) -> dict:
    csrf_from_request(request)
    old = session_from_request(request, refresh=True)
    token = internal_access_token(old)
    with MasterSessionLocal() as db:
        db_row = db.get(AuthSession, old.id)
        if db_row is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail={"code": "SESSION_INVALID", "message": "Sua sessao nao e valida. Entre novamente."})
        db_row.revoked_at = datetime.now(UTC)
        new_row, session_token, csrf_token = _create_row(
            token,
            request,
            refresh_expires_at=db_row.refresh_expires_at,
            last_seen_at=db_row.last_seen_at,
        )
        db.add(new_row)
        db.flush()
        new_claims = dict(new_row.claims)
        db_row.replaced_by_id = new_row.id
        _audit(db, "session_rotated", request, new_row, metadata={"replaced_session_id": db_row.id})
        db.commit()
        _set_cookies(response, session_token, csrf_token)
    return new_claims


def revoke_session(request: Request, response: Response) -> None:
    csrf_from_request(request)
    token = request.cookies.get(SESSION_COOKIE)
    with MasterSessionLocal() as db:
        row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(token or "")))
        if row is not None and row.revoked_at is None:
            row.revoked_at = datetime.now(UTC)
            _audit(db, "session_revoked", request, row)
            db.commit()
    _clear_cookies(response)

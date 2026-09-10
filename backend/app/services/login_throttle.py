from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib

from fastapi import HTTPException, Request, status
from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.auth_session import SecurityAuditLog

WINDOW = timedelta(minutes=15)
MAX_FAILURES = 5


def _attempt_key(request: Request, company_code: str, email: str) -> str:
    ip = request.client.host if request.client else "unknown"
    value = "|".join((company_code.strip().lower(), email.strip().lower(), ip))
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _write_attempt(
    request: Request,
    company_code: str,
    email: str,
    outcome: str,
) -> None:
    try:
        with MasterSessionLocal() as db:
            db.add(
                SecurityAuditLog(
                    event="login_attempt",
                    outcome=outcome,
                    ip_address=request.client.host if request.client else None,
                    user_agent=request.headers.get("user-agent"),
                    metadata_json={
                        "attempt_key": _attempt_key(request, company_code, email),
                    },
                )
            )
            db.commit()
    except Exception:
        # Login protection must never turn a database/audit outage into a
        # misleading authentication failure.
        return


def enforce_login_rate_limit(
    request: Request,
    company_code: str,
    email: str,
) -> None:
    now = datetime.now(UTC)
    cutoff = now - WINDOW
    key = _attempt_key(request, company_code, email)
    try:
        with MasterSessionLocal() as db:
            rows = db.scalars(
                select(SecurityAuditLog)
                .where(
                    SecurityAuditLog.event == "login_attempt",
                    SecurityAuditLog.outcome == "failure",
                    SecurityAuditLog.created_at >= cutoff,
                )
                .order_by(SecurityAuditLog.created_at.desc())
            ).all()
            failures = sum(
                1
                for row in rows
                if (row.metadata_json or {}).get("attempt_key") == key
            )
    except Exception:
        return

    if failures >= MAX_FAILURES:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Nao foi possivel autenticar agora. Tente novamente em alguns minutos.",
            headers={"Retry-After": str(int(WINDOW.total_seconds()))},
        )


def record_login_failure(request: Request, company_code: str, email: str) -> None:
    _write_attempt(request, company_code, email, "failure")


def record_login_success(request: Request, company_code: str, email: str) -> None:
    _write_attempt(request, company_code, email, "success")

"""Safe learning-event collection for Lyna.

Daily learning is external knowledge, not live weight updates. Events are
sanitized, tenant-local, and pending review. Nothing captured here becomes a
global rule automatically.
"""

from __future__ import annotations

import re
from threading import Lock

from sqlalchemy.orm import Session

from app.models.lyna import LynaLearningEvent
from app.models.user import User


_table_lock = Lock()
_initialized_bind_keys: set[str] = set()


def ensure_learning_table(db: Session) -> None:
    bind = db.get_bind()
    bind_key = str(bind.url)
    if bind_key in _initialized_bind_keys:
        return
    with _table_lock:
        if bind_key not in _initialized_bind_keys:
            LynaLearningEvent.__table__.create(bind=bind, checkfirst=True)
            _initialized_bind_keys.add(bind_key)


def sanitize_learning_text(value: str, limit: int = 4000) -> str:
    """Remove common secrets/PII before an event is persisted."""

    sanitized = value or ""
    patterns = (
        (r"\b\d{11}\b", "[CPF]"),
        (r"\b\d{14}\b", "[CNPJ]"),
        (r"\b\d{44}\b", "[CHAVE_NFE]"),
        (r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[EMAIL]"),
        (r"(?<!\d)(?:\+?55\s?)?(?:\(?\d{2}\)?\s?)?9?\d{4}[-\s]?\d{4}(?!\d)", "[TELEFONE]"),
        (r"(?i)\b(?:senha|password|token|api[_ -]?key|secret)\s*[:=]\s*\S+", "[SEGREDO_REMOVIDO]"),
        (r"R\$\s*[\d.,]+", "[VALOR]"),
    )
    for pattern, replacement in patterns:
        sanitized = re.sub(pattern, replacement, sanitized)
    return sanitized.strip()[:limit]


def record_learning_event(
    db: Session,
    user: User,
    *,
    question: str,
    answer: str,
    screen: str,
    module: str,
    source: str,
    model: str | None,
) -> None:
    """Persist a review candidate without affecting ERP domain data."""

    if not answer.strip() or source not in {"ollama", "fallback"}:
        return
    try:
        ensure_learning_table(db)
        db.add(
            LynaLearningEvent(
                user_id=user.id,
                question=sanitize_learning_text(question),
                answer=sanitize_learning_text(answer),
                screen=sanitize_learning_text(screen, 120),
                module=sanitize_learning_text(module, 80),
                source=source,
                model=model,
                risk_level="fiscal_review" if any(
                    term in f"{question} {screen} {module}".lower()
                    for term in ("fiscal", "nfe", "nfce", "nfse", "sefaz", "cfop", "cst")
                ) else "normal",
                status="pending_review",
            )
        )
        db.commit()
    except Exception:
        # Learning must never make the assistant or the ERP unavailable.
        db.rollback()

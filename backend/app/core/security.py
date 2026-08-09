import base64
import hashlib
import hmac
import os
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt

from app.core.config import get_settings

PBKDF2_ITERATIONS = 600_000
SALT_BYTES = 16
HASH_BYTES = 32
PASSWORD_HASH_PREFIX = "pbkdf2_sha256"
JWT_ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    salt = os.urandom(SALT_BYTES)
    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PBKDF2_ITERATIONS,
        dklen=HASH_BYTES,
    )
    salt_b64 = base64.b64encode(salt).decode("ascii")
    hash_b64 = base64.b64encode(password_hash).decode("ascii")
    return f"{PASSWORD_HASH_PREFIX}${PBKDF2_ITERATIONS}${salt_b64}${hash_b64}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        prefix, iterations_text, salt_b64, hash_b64 = stored_hash.split("$", 3)
        if prefix != PASSWORD_HASH_PREFIX:
            return False

        iterations = int(iterations_text)
        salt = base64.b64decode(salt_b64.encode("ascii"))
        expected_hash = base64.b64decode(hash_b64.encode("ascii"))
    except (ValueError, TypeError):
        return False

    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        iterations,
        dklen=len(expected_hash),
    )
    return hmac.compare_digest(password_hash, expected_hash)


def create_access_token(
    subject: str,
    extra_claims: dict[str, Any] | None = None,
    expires_minutes: int | None = None,
) -> str:
    settings = get_settings()
    expires_at = datetime.now(UTC) + timedelta(
        minutes=expires_minutes or settings.access_token_expire_minutes
    )
    payload: dict[str, Any] = {
        "sub": subject,
        "exp": expires_at,
        "iat": datetime.now(UTC),
        "type": "access",
    }
    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, settings.secret_key, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any]:
    settings = get_settings()
    return jwt.decode(token, settings.secret_key, algorithms=[JWT_ALGORITHM])


def decode_access_token_unverified_exp(token: str) -> dict[str, Any]:
    settings = get_settings()
    return jwt.decode(
        token,
        settings.secret_key,
        algorithms=[JWT_ALGORITHM],
        options={"verify_exp": False},
    )


def generate_agent_token() -> str:
    return secrets.token_urlsafe(32)


def hash_agent_token(token: str) -> str:
    return hash_password(token)


def verify_agent_token(token: str, stored_hash: str | None) -> bool:
    if not stored_hash:
        return False
    return verify_password(token, stored_hash)

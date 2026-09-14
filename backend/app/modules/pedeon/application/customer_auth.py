from dataclasses import dataclass

from fastapi import HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import create_access_token, hash_password, verify_password
from app.modules.pedeon.infrastructure.database.models import PedeOnCustomer, PedeOnStore


@dataclass(frozen=True)
class CustomerIdentity:
    customer_id: int
    store_id: int
    name: str
    email: str
    phone: str | None


CUSTOMER_SESSION_COOKIE = "pedeon_customer_session"
_SESSION_MAX_AGE = 60 * 60 * 24 * 30


def _cookie_domain(request: Request) -> str | None:
    host = (request.url.hostname or "").lower().rstrip(".")
    if host == "lyncar.com.br" or host.endswith(".lyncar.com.br"):
        return ".lyncar.com.br"
    return None


def set_customer_cookie(response: Response, request: Request, token: str) -> None:
    response.set_cookie(
        key=CUSTOMER_SESSION_COOKIE,
        value=token,
        max_age=_SESSION_MAX_AGE,
        httponly=True,
        secure=request.url.scheme == "https",
        samesite="lax",
        path="/pedeon/public",
        domain=_cookie_domain(request),
    )


def clear_customer_cookie(response: Response, request: Request) -> None:
    response.delete_cookie(
        key=CUSTOMER_SESSION_COOKIE,
        httponly=True,
        secure=request.url.scheme == "https",
        samesite="lax",
        path="/pedeon/public",
        domain=_cookie_domain(request),
    )


def normalize_email(email: str) -> str:
    return email.strip().lower()


def token_for(customer: PedeOnCustomer, slug: str) -> str:
    return create_access_token(
        f"pedeon_customer:{customer.id}",
        extra_claims={
            "scope": "pedeon_customer",
            "customer_id": customer.id,
            "store_id": customer.store_id,
            "store_slug": slug,
        },
        expires_minutes=60 * 24 * 30,
    )


def identity(customer: PedeOnCustomer) -> CustomerIdentity:
    return CustomerIdentity(
        customer_id=customer.id,
        store_id=customer.store_id,
        name=customer.name,
        email=customer.email,
        phone=customer.phone,
    )


def read_customer(request: Request, db: Session, store: PedeOnStore) -> PedeOnCustomer:
    authorization = request.headers.get("Authorization", "")
    token = (
        authorization.split(" ", 1)[1].strip()
        if authorization.lower().startswith("bearer ")
        else request.cookies.get(CUSTOMER_SESSION_COOKIE)
    )
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Entre para continuar.")
    from app.core.security import decode_access_token
    try:
        claims = decode_access_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Sua sessão expirou. Entre novamente.") from exc
    if claims.get("scope") != "pedeon_customer" or claims.get("store_slug") != store.public_slug:
        raise HTTPException(status_code=401, detail="Sessão de cliente inválida para esta loja.")
    customer = db.scalar(
        select(PedeOnCustomer).where(
            PedeOnCustomer.id == claims.get("customer_id"),
            PedeOnCustomer.store_id == store.id,
            PedeOnCustomer.active.is_(True),
        )
    )
    if customer is None:
        raise HTTPException(status_code=401, detail="Conta de cliente não encontrada.")
    return customer


def public_customer(customer: PedeOnCustomer, token: str) -> dict:
    return {
        "access_token": token,
        "token_type": "bearer",
        "customer": {
            "id": customer.id,
            "name": customer.name,
            "email": customer.email,
            "phone": customer.phone,
            "document": customer.document_number,
            "delivery_address": customer.delivery_address,
        },
    }

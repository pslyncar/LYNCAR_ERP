from dataclasses import dataclass

from fastapi import HTTPException, Request, status
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
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Entre para continuar.")
    from app.core.security import decode_access_token
    try:
        claims = decode_access_token(authorization.split(" ", 1)[1].strip())
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
        },
    }

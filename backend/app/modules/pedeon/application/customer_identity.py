from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.master_database import MasterSessionLocal
from app.models.master_pedeon_customer import (
    MasterPedeOnCustomer,
    MasterPedeOnCustomerIdentity,
    MasterPedeOnCustomerStoreLink,
)
from app.modules.pedeon.infrastructure.database.models import PedeOnCustomer, PedeOnStore


def global_customer_for(
    *,
    email: str,
    name: str,
    phone: str | None = None,
    password_hash: str | None = None,
    provider: str | None = None,
    provider_subject: str | None = None,
) -> MasterPedeOnCustomer:
    """Find or create the platform identity and its optional social identity."""
    normalized_email = email.strip().lower()
    with MasterSessionLocal() as db:
        customer = None
        if provider and provider_subject:
            identity = db.scalar(
                select(MasterPedeOnCustomerIdentity).where(
                    MasterPedeOnCustomerIdentity.provider == provider,
                    MasterPedeOnCustomerIdentity.provider_subject == provider_subject,
                )
            )
            if identity:
                customer = db.get(MasterPedeOnCustomer, identity.customer_id)
        if customer is None:
            customer = db.scalar(
                select(MasterPedeOnCustomer).where(MasterPedeOnCustomer.email == normalized_email)
            )
        if customer is None:
            customer = MasterPedeOnCustomer(
                email=normalized_email,
                name=name.strip() or normalized_email.split("@", 1)[0],
                phone=phone,
                password_hash=password_hash,
                active=True,
            )
            db.add(customer)
            db.flush()
        else:
            if name.strip():
                customer.name = name.strip()
            if phone:
                customer.phone = phone
            if password_hash and not customer.password_hash:
                customer.password_hash = password_hash
        if provider and provider_subject:
            existing_identity = db.scalar(
                select(MasterPedeOnCustomerIdentity).where(
                    MasterPedeOnCustomerIdentity.provider == provider,
                    MasterPedeOnCustomerIdentity.provider_subject == provider_subject,
                )
            )
            if existing_identity is None:
                db.add(
                    MasterPedeOnCustomerIdentity(
                        customer_id=customer.id,
                        provider=provider,
                        provider_subject=provider_subject,
                    )
                )
        db.commit()
        db.refresh(customer)
        return customer


def attach_local_customer(
    db: Session,
    store: PedeOnStore,
    company_code: str,
    global_customer: MasterPedeOnCustomer,
) -> PedeOnCustomer:
    """Create or upgrade the store-local projection of a global customer."""
    customer = db.scalar(
        select(PedeOnCustomer).where(
            PedeOnCustomer.store_id == store.id,
            PedeOnCustomer.global_customer_id == global_customer.id,
        )
    )
    if customer is None:
        customer = db.scalar(
            select(PedeOnCustomer).where(
                PedeOnCustomer.store_id == store.id,
                PedeOnCustomer.email == global_customer.email,
            )
        )
    if customer is None:
        customer = PedeOnCustomer(
            store_id=store.id,
            global_customer_id=global_customer.id,
            name=global_customer.name,
            email=global_customer.email,
            phone=global_customer.phone,
            document_number=global_customer.document_number,
            delivery_address=global_customer.delivery_address,
            password_hash=global_customer.password_hash,
            provider="global",
            active=global_customer.active,
        )
        db.add(customer)
    else:
        customer.global_customer_id = global_customer.id
        customer.name = global_customer.name
        customer.phone = global_customer.phone
        customer.document_number = global_customer.document_number
        customer.delivery_address = global_customer.delivery_address
        customer.password_hash = global_customer.password_hash
        customer.active = global_customer.active
    db.flush()
    with MasterSessionLocal() as master_db:
        link = master_db.scalar(
            select(MasterPedeOnCustomerStoreLink).where(
                MasterPedeOnCustomerStoreLink.customer_id == global_customer.id,
                MasterPedeOnCustomerStoreLink.company_code == company_code,
                MasterPedeOnCustomerStoreLink.store_slug == store.public_slug,
            )
        )
        if link is None:
            master_db.add(
                MasterPedeOnCustomerStoreLink(
                    customer_id=global_customer.id,
                    company_code=company_code,
                    store_slug=store.public_slug,
                    local_customer_id=customer.id,
                )
            )
        else:
            link.local_customer_id = customer.id
        master_db.commit()
    return customer


def update_global_profile(customer: PedeOnCustomer) -> None:
    if customer.global_customer_id is None:
        return
    with MasterSessionLocal() as db:
        global_customer = db.get(MasterPedeOnCustomer, customer.global_customer_id)
        if global_customer is None:
            return
        global_customer.name = customer.name
        global_customer.phone = customer.phone
        global_customer.document_number = customer.document_number
        global_customer.delivery_address = customer.delivery_address
        global_customer.updated_at = datetime.now(timezone.utc)
        db.commit()

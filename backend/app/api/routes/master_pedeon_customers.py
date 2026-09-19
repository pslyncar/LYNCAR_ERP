from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.master_pedeon_customer import (
    MasterPedeOnCustomer,
    MasterPedeOnCustomerStoreLink,
)
from app.schemas.master_pedeon_customer import (
    MasterPedeOnCustomerRead,
    MasterPedeOnCustomerStatusUpdate,
)

router = APIRouter()


@router.get("/pedeon-customers", response_model=list[MasterPedeOnCustomerRead])
def list_pedeon_customers(
    search: str | None = Query(default=None, max_length=180),
    _user=Depends(require_master_permission("master:integrations")),
):
    with MasterSessionLocal() as db:
        query = select(MasterPedeOnCustomer).order_by(MasterPedeOnCustomer.created_at.desc())
        if search and search.strip():
            value = f"%{search.strip().lower()}%"
            query = query.where(
                func.lower(MasterPedeOnCustomer.email).like(value)
                | func.lower(MasterPedeOnCustomer.name).like(value)
            )
        customers = list(db.scalars(query.limit(200)).all())
        counts = dict(
            db.execute(
                select(
                    MasterPedeOnCustomerStoreLink.customer_id,
                    func.count(MasterPedeOnCustomerStoreLink.id),
                )
                .where(
                    MasterPedeOnCustomerStoreLink.customer_id.in_(
                        [customer.id for customer in customers]
                    )
                )
                .group_by(MasterPedeOnCustomerStoreLink.customer_id)
            ).all()
        )
        return [
            MasterPedeOnCustomerRead(
                id=customer.id,
                email=customer.email,
                name=customer.name,
                phone=customer.phone,
                active=customer.active,
                blocked_at=customer.blocked_at,
                linked_stores=counts.get(customer.id, 0),
                created_at=customer.created_at,
            )
            for customer in customers
        ]


@router.patch("/pedeon-customers/{customer_id}", response_model=MasterPedeOnCustomerRead)
def update_pedeon_customer_status(
    customer_id: int,
    payload: MasterPedeOnCustomerStatusUpdate,
    _user=Depends(require_master_permission("master:integrations")),
):
    with MasterSessionLocal() as db:
        customer = db.get(MasterPedeOnCustomer, customer_id)
        if customer is None:
            from fastapi import HTTPException
            raise HTTPException(status_code=404, detail="Cliente PedeOn não encontrado.")
        customer.active = payload.active
        customer.blocked_at = None if payload.active else datetime.now(timezone.utc)
        db.commit()
        db.refresh(customer)
        linked_stores = db.scalar(
            select(func.count(MasterPedeOnCustomerStoreLink.id)).where(
                MasterPedeOnCustomerStoreLink.customer_id == customer.id
            )
        ) or 0
        return MasterPedeOnCustomerRead(
            id=customer.id,
            email=customer.email,
            name=customer.name,
            phone=customer.phone,
            active=customer.active,
            blocked_at=customer.blocked_at,
            linked_stores=linked_stores,
            created_at=customer.created_at,
        )

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.subscription_plan import SubscriptionPlan
from app.models.website_contact_request import WebsiteContactRequest
from app.schemas.subscription_plan import SubscriptionPlanRead
from app.schemas.website_contact_request import (
    WebsiteContactRequestCreate,
    WebsiteContactRequestRead,
)


router = APIRouter()


@router.get("/plans", response_model=list[SubscriptionPlanRead])
def list_public_plans(response: Response) -> list[SubscriptionPlan]:
    """Expose only active commercial plans for the institutional website."""
    with MasterSessionLocal() as db:
        plans = list(
            db.scalars(
                select(SubscriptionPlan)
                .where(SubscriptionPlan.active.is_(True))
                .order_by(SubscriptionPlan.sort_order, SubscriptionPlan.id)
            ).all()
        )
        response.headers["Cache-Control"] = "public, max-age=60, stale-while-revalidate=300"
        return plans


@router.post(
    "/contact-requests",
    response_model=WebsiteContactRequestRead,
    status_code=status.HTTP_201_CREATED,
)
def create_contact_request(
    contact_in: WebsiteContactRequestCreate,
) -> WebsiteContactRequest:
    if contact_in.website:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Solicitacao invalida.",
        )
    contact = WebsiteContactRequest(
        **contact_in.model_dump(exclude={"website"}),
    )
    with MasterSessionLocal() as db:
        db.add(contact)
        db.commit()
        db.refresh(contact)
        return contact

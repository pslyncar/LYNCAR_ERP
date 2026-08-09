from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.website_contact_request import WebsiteContactRequest
from app.schemas.website_contact_request import (
    WebsiteContactRequestRead,
    WebsiteContactRequestStatusUpdate,
)

router = APIRouter()


@router.get("/contact-requests", response_model=list[WebsiteContactRequestRead])
def list_contact_requests(
    request_status: str | None = Query(default=None, alias="status"),
    search: str | None = None,
    _: dict = Depends(require_master_permission("master:companies")),
) -> list[WebsiteContactRequest]:
    with MasterSessionLocal() as db:
        query = select(WebsiteContactRequest)
        if request_status:
            query = query.where(WebsiteContactRequest.status == request_status)
        if search and search.strip():
            term = f"%{search.strip()}%"
            query = query.where(
                or_(
                    WebsiteContactRequest.name.ilike(term),
                    WebsiteContactRequest.phone.ilike(term),
                    WebsiteContactRequest.email.ilike(term),
                    WebsiteContactRequest.company_name.ilike(term),
                )
            )
        return list(
            db.scalars(
                query.order_by(WebsiteContactRequest.created_at.desc())
            ).all()
        )


@router.patch(
    "/contact-requests/{request_id}",
    response_model=WebsiteContactRequestRead,
)
def update_contact_request_status(
    request_id: int,
    update: WebsiteContactRequestStatusUpdate,
    _: dict = Depends(require_master_permission("master:companies")),
) -> WebsiteContactRequest:
    with MasterSessionLocal() as db:
        contact = db.get(WebsiteContactRequest, request_id)
        if contact is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Solicitacao de contato nao encontrada.",
            )
        contact.status = update.status
        db.commit()
        db.refresh(contact)
        return contact

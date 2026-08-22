from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.business_segment import BusinessSegment
from app.models.company import Company
from app.schemas.business_segment import (
    BusinessSegmentCreate,
    BusinessSegmentRead,
    BusinessSegmentUpdate,
)
from app.services.company_modules import normalize_modules

router = APIRouter()


@router.get("/segments", response_model=list[BusinessSegmentRead])
def list_segments(
    _: dict = Depends(require_master_permission("master:billing")),
) -> list[BusinessSegment]:
    with MasterSessionLocal() as db:
        return list(
            db.scalars(
                select(BusinessSegment).order_by(
                    BusinessSegment.sort_order,
                    BusinessSegment.id,
                )
            ).all()
        )


@router.post(
    "/segments",
    response_model=BusinessSegmentRead,
    status_code=status.HTTP_201_CREATED,
)
def create_segment(
    segment_in: BusinessSegmentCreate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> BusinessSegment:
    code = segment_in.code.strip().lower().replace(" ", "_")
    with MasterSessionLocal() as db:
        existing = db.scalar(select(BusinessSegment).where(BusinessSegment.code == code))
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Segmento ja existe.",
            )
        segment = BusinessSegment(
            code=code,
            name=segment_in.name.strip(),
            description=segment_in.description,
            max_users=segment_in.max_users,
            max_pdv_terminals=segment_in.max_pdv_terminals,
            default_modules=normalize_modules(segment_in.default_modules),
            seller_role_enabled=segment_in.seller_role_enabled,
            technician_role_enabled=segment_in.technician_role_enabled,
            active=segment_in.active,
            sort_order=segment_in.sort_order,
        )
        db.add(segment)
        db.commit()
        db.refresh(segment)
        return segment


@router.put("/segments/{segment_code}", response_model=BusinessSegmentRead)
def update_segment(
    segment_code: str,
    segment_in: BusinessSegmentUpdate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> BusinessSegment:
    with MasterSessionLocal() as db:
        segment = db.scalar(select(BusinessSegment).where(BusinessSegment.code == segment_code))
        if segment is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Segmento nao encontrado.",
            )
        segment.name = segment_in.name.strip()
        segment.description = segment_in.description
        segment.max_users = segment_in.max_users
        segment.max_pdv_terminals = segment_in.max_pdv_terminals
        segment.default_modules = normalize_modules(segment_in.default_modules)
        segment.seller_role_enabled = segment_in.seller_role_enabled
        segment.technician_role_enabled = segment_in.technician_role_enabled
        segment.active = segment_in.active
        segment.sort_order = segment_in.sort_order
        db.commit()
        db.refresh(segment)
        return segment


@router.delete("/segments/{segment_code}", status_code=status.HTTP_204_NO_CONTENT)
def delete_segment(
    segment_code: str,
    migrate_to_segment: str | None = None,
    _: dict = Depends(require_master_permission("master:billing")),
) -> None:
    if segment_code == "custom":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="O segmento Personalizado nao pode ser excluido.",
        )
    with MasterSessionLocal() as db:
        segment = db.scalar(select(BusinessSegment).where(BusinessSegment.code == segment_code))
        if segment is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Segmento nao encontrado.",
            )
        companies = list(
            db.scalars(select(Company).where(Company.business_type == segment.code)).all()
        )
        if companies and not migrate_to_segment:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Segmento em uso por {len(companies)} cliente(s). "
                    "Escolha outro segmento para migrar antes de excluir."
                ),
            )
        if companies:
            if migrate_to_segment == segment.code:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Escolha um segmento de destino diferente do segmento excluido.",
                )
            destination = db.scalar(
                select(BusinessSegment).where(BusinessSegment.code == migrate_to_segment)
            )
            if destination is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Segmento de destino nao encontrado.",
                )
            for company in companies:
                company.business_type = destination.code
        db.delete(segment)
        db.commit()

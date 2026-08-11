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
from app.services.company_modules import normalize_modules, seed_business_segments

router = APIRouter()


@router.get("/segments", response_model=list[BusinessSegmentRead])
def list_segments(
    _: dict = Depends(require_master_permission("master:billing")),
) -> list[BusinessSegment]:
    with MasterSessionLocal() as db:
        seed_business_segments(db)
        db.commit()
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
        seed_business_segments(db)
        db.commit()
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
            default_modules=normalize_modules(segment_in.default_modules),
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
        seed_business_segments(db)
        db.commit()
        segment = db.scalar(select(BusinessSegment).where(BusinessSegment.code == segment_code))
        if segment is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Segmento nao encontrado.",
            )
        segment.name = segment_in.name.strip()
        segment.description = segment_in.description
        segment.default_modules = normalize_modules(segment_in.default_modules)
        segment.active = segment_in.active
        segment.sort_order = segment_in.sort_order
        db.commit()
        db.refresh(segment)
        return segment


@router.delete("/segments/{segment_code}", status_code=status.HTTP_204_NO_CONTENT)
def delete_segment(
    segment_code: str,
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
        in_use = db.scalar(
            select(Company.id).where(Company.business_type == segment.code).limit(1)
        )
        if in_use is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Segmento em uso por cliente. Desative ou altere os clientes antes de excluir.",
            )
        db.delete(segment)
        db.commit()

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.dashboard_content import DashboardContent
from app.schemas.dashboard_content import (
    DashboardContentCreate,
    DashboardContentRead,
    DashboardContentUpdate,
)

router = APIRouter()


@router.get("/dashboard-contents", response_model=list[DashboardContentRead])
def list_dashboard_contents(_: dict = Depends(require_master_permission("master:content"))) -> list[DashboardContent]:
    with MasterSessionLocal() as db:
        return list(
            db.scalars(
                select(DashboardContent).order_by(
                    DashboardContent.sort_order,
                    DashboardContent.id.desc(),
                )
            ).all()
        )


@router.post(
    "/dashboard-contents",
    response_model=DashboardContentRead,
    status_code=status.HTTP_201_CREATED,
)
def create_dashboard_content(
    content_in: DashboardContentCreate,
    _: dict = Depends(require_master_permission("master:content")),
) -> DashboardContent:
    with MasterSessionLocal() as db:
        content = DashboardContent(**content_in.model_dump())
        db.add(content)
        db.commit()
        db.refresh(content)
        return content


@router.put("/dashboard-contents/{content_id}", response_model=DashboardContentRead)
def update_dashboard_content(
    content_id: int,
    content_in: DashboardContentUpdate,
    _: dict = Depends(require_master_permission("master:content")),
) -> DashboardContent:
    with MasterSessionLocal() as db:
        content = db.get(DashboardContent, content_id)
        if content is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conteudo da dashboard nao encontrado.",
            )
        for field, value in content_in.model_dump(exclude_unset=True).items():
            setattr(content, field, value)
        db.commit()
        db.refresh(content)
        return content


@router.delete("/dashboard-contents/{content_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_dashboard_content(
    content_id: int,
    _: dict = Depends(require_master_permission("master:content")),
) -> None:
    with MasterSessionLocal() as db:
        content = db.get(DashboardContent, content_id)
        if content is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conteudo da dashboard nao encontrado.",
            )
        db.delete(content)
        db.commit()

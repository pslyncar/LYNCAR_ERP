from fastapi import APIRouter, Depends, HTTPException

from app.api.dependencies import require_master_permission
from app.schemas.plan_change import (
    PlanChangeApplyRequest,
    PlanChangePreview,
    PlanChangePreviewRequest,
    PlanChangeResult,
)
from app.services.plan_change import apply_plan_change, preview_plan_change

router = APIRouter()


@router.post("/companies/{company_id}/plan-change/preview", response_model=PlanChangePreview)
def preview_company_plan_change(
    company_id: int,
    payload: PlanChangePreviewRequest,
    _: dict = Depends(require_master_permission("master:companies")),
) -> PlanChangePreview:
    return preview_plan_change(company_id, payload.target_plan, payload.target_business_type)


@router.post("/companies/{company_id}/plan-change", response_model=PlanChangeResult)
def change_company_plan(
    company_id: int,
    payload: PlanChangeApplyRequest,
    _: dict = Depends(require_master_permission("master:companies")),
) -> PlanChangeResult:
    return apply_plan_change(
        company_id,
        payload.target_plan,
        payload.target_business_type,
        payload.user_ids,
        payload.terminal_ids,
    )

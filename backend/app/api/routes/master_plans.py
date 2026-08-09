from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.subscription_plan import SubscriptionPlan
from app.schemas.subscription_plan import SubscriptionPlanRead, SubscriptionPlanUpdate
from app.services.plan_limits import seed_subscription_plans

router = APIRouter()


@router.get("/plans", response_model=list[SubscriptionPlanRead])
def list_plans(_: dict = Depends(require_master_permission("master:billing"))) -> list[SubscriptionPlan]:
    with MasterSessionLocal() as db:
        seed_subscription_plans(db)
        return list(
            db.scalars(
                select(SubscriptionPlan).order_by(
                    SubscriptionPlan.sort_order,
                    SubscriptionPlan.id,
                )
            ).all()
        )


@router.put("/plans/{plan_code}", response_model=SubscriptionPlanRead)
def update_plan(
    plan_code: str,
    plan_in: SubscriptionPlanUpdate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> SubscriptionPlan:
    with MasterSessionLocal() as db:
        seed_subscription_plans(db)
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == plan_code))
        if plan is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Plano nao encontrado.",
            )
        for field, value in plan_in.model_dump().items():
            setattr(plan, field, value)
        if plan_in.default_modules is not None:
            normalized_modules = sorted(set(plan_in.default_modules))
            companies = db.scalars(
                select(Company).where(Company.plan == plan.code)
            ).all()
            for company in companies:
                company.enabled_modules = normalized_modules
        db.commit()
        db.refresh(plan)
        return plan

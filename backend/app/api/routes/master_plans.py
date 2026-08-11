from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.subscription_plan import SubscriptionPlan
from app.schemas.subscription_plan import (
    SubscriptionPlanCreate,
    SubscriptionPlanRead,
    SubscriptionPlanUpdate,
)
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


@router.post(
    "/plans",
    response_model=SubscriptionPlanRead,
    status_code=status.HTTP_201_CREATED,
)
def create_plan(
    plan_in: SubscriptionPlanCreate,
    _: dict = Depends(require_master_permission("master:billing")),
) -> SubscriptionPlan:
    code = plan_in.code.strip().lower().replace(" ", "_")
    with MasterSessionLocal() as db:
        seed_subscription_plans(db)
        existing = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == code))
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Plano ja existe.",
            )
        data = plan_in.model_dump(exclude={"code"})
        data["default_modules"] = sorted(set(data.get("default_modules") or []))
        plan = SubscriptionPlan(code=code, **data)
        db.add(plan)
        db.commit()
        db.refresh(plan)
        return plan


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


@router.delete("/plans/{plan_code}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan(
    plan_code: str,
    _: dict = Depends(require_master_permission("master:billing")),
) -> None:
    with MasterSessionLocal() as db:
        seed_subscription_plans(db)
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == plan_code))
        if plan is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Plano nao encontrado.",
            )
        in_use = db.scalar(select(Company.id).where(Company.plan == plan.code).limit(1))
        if in_use is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Plano em uso por cliente. Altere os clientes antes de excluir.",
            )
        db.delete(plan)
        db.commit()

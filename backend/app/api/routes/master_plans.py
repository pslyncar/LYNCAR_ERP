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

router = APIRouter()


@router.get("/plans", response_model=list[SubscriptionPlanRead])
def list_plans(_: dict = Depends(require_master_permission("master:billing"))) -> list[SubscriptionPlan]:
    with MasterSessionLocal() as db:
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
    migrate_to_plan: str | None = None,
    _: dict = Depends(require_master_permission("master:billing")),
) -> None:
    with MasterSessionLocal() as db:
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == plan_code))
        if plan is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Plano nao encontrado.",
            )
        companies = list(db.scalars(select(Company).where(Company.plan == plan.code)).all())
        if companies and not migrate_to_plan:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Plano em uso por {len(companies)} cliente(s). "
                    "Escolha outro plano para migrar antes de excluir."
                ),
            )
        if companies:
            if migrate_to_plan == plan.code:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Escolha um plano de destino diferente do plano excluido.",
                )
            destination = db.scalar(
                select(SubscriptionPlan).where(SubscriptionPlan.code == migrate_to_plan)
            )
            if destination is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Plano de destino nao encontrado.",
                )
            destination_modules = sorted(set(destination.default_modules or []))
            for company in companies:
                company.plan = destination.code
                company.enabled_modules = destination_modules
        db.delete(plan)
        db.commit()

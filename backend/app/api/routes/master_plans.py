from fastapi import APIRouter, Depends, HTTPException, Query, status
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
from app.services.company_modules import modules_for_business_type

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
    apply_to_existing_companies: bool = Query(
        True,
        description="Atualiza empresas que herdaram o plano; concessões personalizadas são preservadas.",
    ),
    _: dict = Depends(require_master_permission("master:billing")),
) -> SubscriptionPlan:
    with MasterSessionLocal() as db:
        plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == plan_code))
        if plan is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Plano nao encontrado.",
            )
        companies = list(db.scalars(select(Company).where(Company.plan == plan.code)).all())
        if not apply_to_existing_companies:
            # Antes de alterar o plano, congela somente quem ainda herdava a
            # configuração. Concessões customizadas não são tocadas.
            for company in companies:
                if getattr(company, "module_access_source", "custom") == "inherited":
                    company.enabled_modules = modules_for_business_type(
                        company.business_type,
                        None,
                        company.plan,
                    )
                    company.module_access_source = "custom"
        for field, value in plan_in.model_dump().items():
            setattr(plan, field, value)
        # Não sobrescreva a configuração específica de cada empresa ao
        # editar o plano. Empresas legadas com enabled_modules nulo continuam
        # herdando plano/segmento dinamicamente.
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
            for company in companies:
                company.plan = destination.code
                # Preserve a decisão específica da empresa. A resolução
                # efetiva passa a considerar o novo plano quando a empresa
                # não possui uma lista explícita.
        db.delete(plan)
        db.commit()

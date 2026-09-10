from fastapi import APIRouter, Depends, HTTPException, Query, status
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
from app.services.company_modules import (
    modules_for_business_type,
    normalize_modules,
    plan_default_modules,
)

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
    apply_to_existing_companies: bool | None = Query(
        None,
        description="Compatibilidade: aplica todas as alterações de módulos.",
    ),
    apply_modules: str | None = Query(
        None,
        description="IDs dos módulos que devem ser aplicados às empresas do segmento.",
    ),
    _: dict = Depends(require_master_permission("master:billing")),
) -> BusinessSegment:
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
        old_segment_modules = set(normalize_modules(segment.default_modules or []))
        new_segment_modules = set(normalize_modules(segment_in.default_modules))
        changed_modules = old_segment_modules ^ new_segment_modules
        if apply_modules is not None:
            selected_modules = {
                module.strip()
                for module in apply_modules.split(",")
                if module.strip()
            } & changed_modules
        elif apply_to_existing_companies is False:
            selected_modules = set()
        else:
            selected_modules = changed_modules
        old_effective_by_company: dict[int, set[str]] = {}
        for company in companies:
            base = set(modules_for_business_type(company.business_type, None, company.plan))
            grants = set(normalize_modules(company.manual_module_grants or []))
            revocations = set(normalize_modules(company.manual_module_revocations or []))
            old_effective_by_company[company.id] = (base | grants) - revocations
        segment.name = segment_in.name.strip()
        segment.description = segment_in.description
        segment.max_users = segment_in.max_users
        segment.max_pdv_terminals = segment_in.max_pdv_terminals
        segment.default_modules = normalize_modules(segment_in.default_modules)
        segment.seller_role_enabled = segment_in.seller_role_enabled
        segment.technician_role_enabled = segment_in.technician_role_enabled
        segment.active = segment_in.active
        segment.sort_order = segment_in.sort_order
        for company in companies:
            new_base = set(
                normalize_modules(
                    sorted(
                        new_segment_modules
                        & set(plan_default_modules(company.plan))
                    )
                )
            )
            grants = set(normalize_modules(company.manual_module_grants or []))
            revocations = set(normalize_modules(company.manual_module_revocations or []))
            # Applying a module makes it inherited again. Remove a previous
            # per-company override only for the buttons selected by the admin.
            for module in selected_modules:
                grants.discard(module)
                revocations.discard(module)
            for module in changed_modules - selected_modules:
                if module in old_effective_by_company[company.id]:
                    grants.add(module)
                    revocations.discard(module)
                else:
                    revocations.add(module)
                    grants.discard(module)
            company.manual_module_grants = sorted(grants)
            company.manual_module_revocations = sorted(revocations)
            company.enabled_modules = sorted((new_base | grants) - revocations)
            company.module_access_source = "custom" if grants or revocations else "inherited"
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
                # A configuração explícita da empresa é preservada. Somente
                # empresas sem lista explícita herdam o novo segmento.
        db.delete(segment)
        db.commit()

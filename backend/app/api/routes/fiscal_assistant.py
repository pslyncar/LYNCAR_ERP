from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.dependencies import get_db, require_permission
from app.core.master_database import MasterSessionLocal
from app.models.product import Product
from app.models.user import User
from app.models.master_fiscal_reference import MasterFiscalNcmCode
from app.schemas.fiscal_assistant import (
    FiscalAssistantProductResponse,
    FiscalReferenceImportRequest,
    FiscalReferenceSyncRead,
)
from app.services.fiscal_assistant import (
    default_tax_suggestion_for_product,
    fiscal_alerts_for_product,
    fiscal_context_for_company,
    collective_fiscal_suggestions,
    fiscal_reference_status,
    fiscal_suggestions_for_product,
    ibs_cbs_class_trib_suggestions,
    ncm_suggestions,
    sync_cest_from_rows,
    sync_cfop_from_rows,
    sync_ibs_cbs_class_trib_from_rows,
    sync_ncm_from_json_payload,
    sync_reference_from_url,
)

router = APIRouter()


@router.get("/product-suggestions", response_model=FiscalAssistantProductResponse)
def get_product_fiscal_suggestions(
    product_id: int | None = None,
    description: str | None = Query(default=None, max_length=220),
    barcode: str | None = Query(default=None, max_length=80),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:read")),
) -> FiscalAssistantProductResponse:
    product = db.get(Product, product_id) if product_id else None
    suggestions = fiscal_suggestions_for_product(
        db,
        product=product,
        description=description,
        barcode=barcode,
    )
    fiscal_context = fiscal_context_for_company(db)
    default_suggestion = default_tax_suggestion_for_product(
        product,
        description=description,
        barcode=barcode,
        fiscal_setting=fiscal_context,
    )
    def _has_core_tax_data(item) -> bool:
        return bool(item.cst or item.csosn or item.cfop or item.origin)

    if not suggestions or not any(_has_core_tax_data(item) for item in suggestions):
        suggestions = [default_suggestion, *suggestions]
    with MasterSessionLocal() as reference_db:
        official_ncm = ncm_suggestions(
            reference_db,
            description or (product.name if product else None),
        )
        product_ncm = "".join(
            char for char in ((product.ncm or "") if product else "") if char.isdigit()
        )
        if product_ncm:
            saved_ncm = reference_db.query(MasterFiscalNcmCode).filter(
                MasterFiscalNcmCode.active.is_(True),
                MasterFiscalNcmCode.code == product_ncm,
            ).first()
            if saved_ncm is not None and all(item.code != saved_ncm.code for item in official_ncm):
                official_ncm = [saved_ncm, *official_ncm]
        official_ibs_cbs = ibs_cbs_class_trib_suggestions(
            reference_db,
            description or (product.name if product else None),
            cst=product.ibs_cbs_cst if product else None,
            ncm=product.ncm if product else None,
        )
        alerts = fiscal_alerts_for_product(product, suggestions, db=reference_db)
    return FiscalAssistantProductResponse(
        suggestions=suggestions,
        collective_suggestions=collective_fiscal_suggestions(
            description=description or (product.name if product else None),
            barcode=barcode or (product.barcode if product else None),
        ),
        ncm_official_suggestions=official_ncm,
        ibs_cbs_official_suggestions=official_ibs_cbs,
        alerts=alerts,
    )


@router.get("/reference/status", response_model=list[FiscalReferenceSyncRead])
def get_fiscal_reference_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:read")),
) -> list:
    with MasterSessionLocal() as reference_db:
        return fiscal_reference_status(reference_db)


@router.post("/reference/import", response_model=list[FiscalReferenceSyncRead])
def import_fiscal_reference(
    payload: FiscalReferenceImportRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("products:update")),
) -> list:
    source_type = payload.source_type.strip().lower()
    with MasterSessionLocal() as reference_db:
        if payload.source_url:
            sync_reference_from_url(reference_db, source_type, payload.source_url)
        elif source_type == "ncm":
            sync_ncm_from_json_payload(reference_db, payload.payload)
        elif source_type == "cfop":
            sync_cfop_from_rows(reference_db, payload.payload if isinstance(payload.payload, list) else [])
        elif source_type == "cest":
            sync_cest_from_rows(reference_db, payload.payload if isinstance(payload.payload, list) else [])
        elif source_type in {"ibs_cbs_class_trib", "cclass_trib", "cclasstrib"}:
            sync_ibs_cbs_class_trib_from_rows(
                reference_db,
                payload.payload if isinstance(payload.payload, list) else [],
            )
        else:
            from fastapi import HTTPException

            raise HTTPException(status_code=400, detail="Fonte fiscal invalida.")
        reference_db.commit()
        return fiscal_reference_status(reference_db)

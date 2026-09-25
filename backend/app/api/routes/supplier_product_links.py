from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.api.dependencies import require_any_permission
from app.core.database import get_db
from app.models.product import Product
from app.models.supplier import Supplier
from app.models.supplier_product_link import SupplierProductLink
from app.models.user import User
from app.schemas.supplier_product_link import (
    SupplierProductLinkRead,
    SupplierProductLinkUpdate,
)

router = APIRouter()


def _read(link: SupplierProductLink) -> SupplierProductLinkRead:
    return SupplierProductLinkRead(
        id=link.id,
        supplier_id=link.supplier_id,
        supplier_name=link.supplier.name,
        product_id=link.product_id,
        product_name=link.product.name,
        product_internal_code=link.product.internal_code,
        supplier_product_code=link.supplier_product_code,
        supplier_description=link.supplier_description,
        commercial_gtin=link.commercial_gtin,
        tax_gtin=link.tax_gtin,
        supplier_unit=link.supplier_unit,
        stock_unit=link.stock_unit,
        conversion_factor=link.conversion_factor,
        last_cost=link.last_cost,
        last_seen_at=link.last_seen_at,
        active=link.active,
    )


@router.get("", response_model=list[SupplierProductLinkRead])
def list_supplier_product_links(
    q: str | None = Query(default=None, max_length=120),
    supplier_id: int | None = Query(default=None, ge=1),
    product_id: int | None = Query(default=None, ge=1),
    active: bool | None = None,
    limit: int = Query(default=200, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:view", "products:view")),
) -> list[SupplierProductLinkRead]:
    query = select(SupplierProductLink).join(SupplierProductLink.supplier).join(SupplierProductLink.product)
    if supplier_id is not None:
        query = query.where(SupplierProductLink.supplier_id == supplier_id)
    if product_id is not None:
        query = query.where(SupplierProductLink.product_id == product_id)
    if active is not None:
        query = query.where(SupplierProductLink.active.is_(active))
    if q and q.strip():
        like = f"%{q.strip()}%"
        query = query.where(
            or_(
                SupplierProductLink.supplier_product_code.ilike(like),
                SupplierProductLink.supplier_description.ilike(like),
                Supplier.name.ilike(like),
                Product.name.ilike(like),
                Product.internal_code.ilike(like),
                SupplierProductLink.commercial_gtin.ilike(like),
                SupplierProductLink.tax_gtin.ilike(like),
            )
        )
    links = db.scalars(
        query.order_by(Supplier.name, Product.name, SupplierProductLink.supplier_product_code)
        .limit(limit)
    ).all()
    return [_read(link) for link in links]


@router.put("/{link_id}", response_model=SupplierProductLinkRead)
def update_supplier_product_link(
    link_id: int,
    payload: SupplierProductLinkUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:create", "products:update")),
) -> SupplierProductLinkRead:
    link = db.get(SupplierProductLink, link_id)
    if link is None:
        raise HTTPException(status_code=404, detail="Vínculo não encontrado.")
    data = payload.model_dump(exclude_unset=True)
    if "supplier_product_code" in data:
        data["supplier_product_code"] = data["supplier_product_code"].strip()
        conflict = db.scalar(
            select(SupplierProductLink).where(
                SupplierProductLink.supplier_id == link.supplier_id,
                SupplierProductLink.supplier_product_code == data["supplier_product_code"],
                SupplierProductLink.id != link.id,
            )
        )
        if conflict is not None:
            raise HTTPException(status_code=409, detail="Este código já está vinculado a outro produto deste fornecedor.")
    for field, value in data.items():
        setattr(link, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(link)
    return _read(link)


@router.delete("/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_supplier_product_link(
    link_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("stock:entries:create", "products:update")),
) -> None:
    link = db.get(SupplierProductLink, link_id)
    if link is None:
        raise HTTPException(status_code=404, detail="Vínculo não encontrado.")
    link.active = False
    db.commit()

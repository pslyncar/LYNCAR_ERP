from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.security import HTTPAuthorizationCredentials

from app.api.dependencies import bearer_scheme, require_any_permission, require_master_permission
from app.core.security import decode_access_token
from app.models.user import User
from app.services.plan_limits import enforce_file_limit
from app.services.tenancy import normalize_company_code
from app.services.uploads import UPLOAD_ROOT, save_public_file, save_public_image

router = APIRouter()


@router.post("/image")
async def upload_tenant_image(
    file: UploadFile = File(...),
    current_user: User = Depends(
        require_any_permission("products:create", "products:update")
    ),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, str]:
    if credentials is None:
        company_code = "tenant"
    else:
        payload = decode_access_token(credentials.credentials)
        company_code = str(payload.get("company_code") or "tenant")
    content = await file.read()
    enforce_file_limit(company_code, UPLOAD_ROOT, len(content))
    file.file.seek(0)
    scope = f"tenant-products-{normalize_company_code(company_code)}"
    return {"url": await save_public_image(file, scope)}


@router.post("/master-image")
async def upload_master_image(
    file: UploadFile = File(...),
    payload: dict = Depends(require_master_permission("master:content")),
) -> dict[str, str]:
    return {"url": await save_public_image(file, "master-dashboard")}


@router.post("/master-contract")
async def upload_master_contract(
    file: UploadFile = File(...),
    payload: dict = Depends(require_master_permission("master:billing")),
) -> dict[str, str]:
    return {
        "url": await save_public_file(file, "master-contracts"),
        "name": file.filename or "contrato",
    }


@router.post("/support-image")
async def upload_support_image(
    file: UploadFile = File(...),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, str]:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Token de acesso ausente.")
    payload = decode_access_token(credentials.credentials)
    company_code = normalize_company_code(str(payload.get("company_code") or "support"))
    content = await file.read()
    enforce_file_limit(company_code, UPLOAD_ROOT, len(content))
    file.file.seek(0)
    return {"url": await save_public_image(file, f"support-{company_code}")}

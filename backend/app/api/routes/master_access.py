from fastapi import APIRouter, Depends

from app.api.dependencies import require_master_permission
from app.services.company_presence import list_master_access_status

router = APIRouter()


@router.get("/access-status")
def read_access_status(_: dict = Depends(require_master_permission("master:companies"))) -> dict:
    return list_master_access_status()

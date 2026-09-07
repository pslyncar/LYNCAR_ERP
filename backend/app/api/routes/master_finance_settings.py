from fastapi import APIRouter, Depends
from sqlalchemy import select

from app.api.dependencies import require_master_permission
from app.core.master_database import MasterSessionLocal
from app.models.master_finance_setting import MasterFinanceSetting
from app.schemas.master_finance_setting import MasterFinanceSettingRead, MasterFinanceSettingUpdate

router = APIRouter()


def _read(row: MasterFinanceSetting) -> MasterFinanceSettingRead:
    return MasterFinanceSettingRead.model_validate(row, from_attributes=True)


def _get(db):
    row = db.scalar(select(MasterFinanceSetting).where(MasterFinanceSetting.id == 1))
    if row is None:
        row = MasterFinanceSetting(id=1)
        db.add(row)
        db.flush()
    return row


@router.get("/finance-settings/billing-policy", response_model=MasterFinanceSettingRead)
def get_billing_policy(_=Depends(require_master_permission("master:billing"))):
    with MasterSessionLocal() as db:
        return _read(_get(db))


@router.put("/finance-settings/billing-policy", response_model=MasterFinanceSettingRead)
def update_billing_policy(payload: MasterFinanceSettingUpdate, _=Depends(require_master_permission("master:billing"))):
    with MasterSessionLocal() as db:
        row = _get(db)
        for key, value in payload.model_dump().items():
            setattr(row, key, value)
        db.commit()
        db.refresh(row)
        return _read(row)

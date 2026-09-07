from datetime import datetime
from pydantic import BaseModel, Field


class MasterFinanceSettingRead(BaseModel):
    late_charges_enabled: bool
    late_fee_percent: float
    late_interest_daily_percent: float
    late_grace_days: int
    monetary_correction_enabled: bool
    monetary_index: str
    automatic_index_update: bool
    updated_at: datetime | None = None


class MasterFinanceSettingUpdate(BaseModel):
    late_charges_enabled: bool = False
    late_fee_percent: float = Field(0, ge=0, le=100)
    late_interest_daily_percent: float = Field(0, ge=0, le=10)
    late_grace_days: int = Field(0, ge=0, le=365)
    monetary_correction_enabled: bool = True
    monetary_index: str = Field("IPCA", pattern="^[A-Z0-9_-]{2,20}$")
    automatic_index_update: bool = True

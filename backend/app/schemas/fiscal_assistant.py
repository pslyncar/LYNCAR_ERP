from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


LEGAL_FISCAL_ASSISTANT_NOTICE = (
    "As informações fiscais são sugestões automáticas do sistema e devem ser "
    "conferidas pelo responsável fiscal ou contador da empresa."
)


class FiscalSuggestionRead(BaseModel):
    id: int
    normalized_description: str
    original_description: str | None = None
    barcode: str | None = None
    unit: str | None = None
    ncm: str | None = None
    cest: str | None = None
    cfop: str | None = None
    origin: str | None = None
    cst: str | None = None
    csosn: str | None = None
    icms_rate: Decimal | None = None
    pis_rate: Decimal | None = None
    cofins_rate: Decimal | None = None
    ipi_rate: Decimal | None = None
    ibs_cbs_cst: str | None = None
    ibs_cbs_classification: str | None = None
    cbs_rate: Decimal | None = None
    ibs_state_rate: Decimal | None = None
    ibs_city_rate: Decimal | None = None
    selective_tax_cst: str | None = None
    selective_tax_classification: str | None = None
    selective_tax_rate: Decimal | None = None
    source: str
    source_reference: str | None = None
    usage_count: int
    last_used_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FiscalAlert(BaseModel):
    severity: str
    field: str | None = None
    message: str


class FiscalReferenceSyncRead(BaseModel):
    source_type: str
    source_name: str
    source_url: str | None = None
    status: str
    records_loaded: int
    message: str | None = None
    synced_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class FiscalNcmSuggestion(BaseModel):
    code: str
    description: str
    source: str = "siscomex_classif"

    model_config = ConfigDict(from_attributes=True)


class FiscalReferenceImportRequest(BaseModel):
    source_type: str
    source_url: str | None = None
    payload: object | None = None


class FiscalAssistantProductResponse(BaseModel):
    legal_notice: str = LEGAL_FISCAL_ASSISTANT_NOTICE
    suggestions: list[FiscalSuggestionRead] = []
    ncm_official_suggestions: list[FiscalNcmSuggestion] = []
    alerts: list[FiscalAlert] = []

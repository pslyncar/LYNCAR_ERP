from pydantic import BaseModel, Field


class PlanChangePreviewRequest(BaseModel):
    target_plan: str = Field(min_length=1)
    target_business_type: str | None = None


class PlanChangeApplyRequest(PlanChangePreviewRequest):
    user_ids: list[int] = Field(default_factory=list)
    terminal_ids: list[int] = Field(default_factory=list)


class PlanChangeItem(BaseModel):
    id: int
    label: str
    detail: str | None = None
    active: bool = True


class PlanChangePreview(BaseModel):
    company_id: int
    company_code: str
    current_plan: str
    target_plan: str
    current_modules: list[str]
    target_modules: list[str]
    removed_modules: list[str]
    users: list[PlanChangeItem]
    terminals: list[PlanChangeItem]
    max_users: int | None
    max_pdv_terminals: int | None
    active_users: int
    active_terminals: int
    required_user_selections: int
    required_terminal_selections: int
    pdv_windows_will_be_revoked: bool


class PlanChangeResult(BaseModel):
    company_id: int
    target_plan: str
    inactivated_user_ids: list[int]
    revoked_terminal_ids: list[int]
    target_modules: list[str]

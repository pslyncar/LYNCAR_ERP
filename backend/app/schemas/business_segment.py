from pydantic import BaseModel, Field


class BusinessSegmentRead(BaseModel):
    id: int
    code: str
    name: str
    description: str | None
    default_modules: list[str] = []
    active: bool
    sort_order: int

    model_config = {"from_attributes": True}


class BusinessSegmentCreate(BaseModel):
    code: str = Field(min_length=2, max_length=60)
    name: str = Field(min_length=2, max_length=100)
    description: str | None = Field(default=None, max_length=220)
    default_modules: list[str] = []
    active: bool = True
    sort_order: int = 0


class BusinessSegmentUpdate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    description: str | None = Field(default=None, max_length=220)
    default_modules: list[str] = []
    active: bool = True
    sort_order: int = 0

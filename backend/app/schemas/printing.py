from typing import Literal

from pydantic import BaseModel, Field


class ThermalPrintRequest(BaseModel):
    printer_host: str = Field(min_length=3, max_length=120)
    printer_port: int = Field(default=9100, ge=1, le=65535)
    paper_width: Literal[58, 80] = 80
    copies: int = Field(default=1, ge=1, le=3)


class ThermalPrintResponse(BaseModel):
    message: str

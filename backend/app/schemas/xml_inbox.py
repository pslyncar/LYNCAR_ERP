from datetime import datetime

from pydantic import BaseModel, Field


class XmlInboxSettingsRead(BaseModel):
    email_address: str
    enabled: bool


class XmlInboxMessageRead(BaseModel):
    id: int
    stock_entry_id: int | None
    status: str
    sender_email: str | None
    subject: str | None
    attachment_name: str | None
    supplier_name: str | None
    supplier_document: str | None
    recipient_document: str | None
    invoice_key: str | None
    invoice_number: str | None
    rejection_reason: str | None
    received_at: datetime

    model_config = {"from_attributes": True}


class XmlInboundPayload(BaseModel):
    sender_email: str | None = Field(default=None, max_length=180)
    subject: str | None = Field(default=None, max_length=240)
    attachment_name: str = Field(default="nfe.xml", max_length=240)
    xml_content: str = Field(min_length=20)


class XmlInboundResult(BaseModel):
    accepted: bool
    status: str
    message: str
    stock_entry_id: int | None = None

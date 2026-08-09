from datetime import datetime

from pydantic import BaseModel, Field


class MasterSupportMessageRead(BaseModel):
    id: int
    ticket_id: int
    author_type: str
    author_user_id: int | None = None
    author_name: str | None = None
    author_email: str | None = None
    body: str
    attachment_url: str | None = None
    attachment_name: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class MasterSupportTicketCreate(BaseModel):
    module: str = Field(default="outro", max_length=40)
    priority: str = Field(default="normal", max_length=20)
    subject: str = Field(min_length=3, max_length=180)
    description: str = Field(min_length=5, max_length=6000)
    attachment_url: str | None = Field(default=None, max_length=2000)
    attachment_name: str | None = Field(default=None, max_length=220)


class MasterSupportTicketUpdate(BaseModel):
    status: str | None = Field(default=None, max_length=30)
    priority: str | None = Field(default=None, max_length=20)
    customer_attachments_enabled: bool | None = None
    assigned_master_user_id: int | None = None


class MasterSupportReplyCreate(BaseModel):
    body: str = Field(min_length=1, max_length=6000)
    status: str | None = Field(default=None, max_length=30)
    attachment_url: str | None = Field(default=None, max_length=2000)
    attachment_name: str | None = Field(default=None, max_length=220)


class MasterSupportTicketRead(BaseModel):
    id: int
    company_id: int
    company_code: str
    company_name: str
    module: str
    priority: str
    status: str
    subject: str
    description: str
    requester_user_id: int | None = None
    requester_name: str | None = None
    requester_email: str | None = None
    customer_attachments_enabled: bool = False
    assigned_master_user_id: int | None = None
    assigned_master_user_name: str | None = None
    assigned_master_user_email: str | None = None
    first_response_at: datetime | None = None
    resolved_at: datetime | None = None
    closed_at: datetime | None = None
    last_message_at: datetime
    created_at: datetime
    updated_at: datetime
    messages: list[MasterSupportMessageRead] = []

    model_config = {"from_attributes": True}

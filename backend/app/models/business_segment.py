from sqlalchemy import Boolean, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.master_database import MasterBase


class BusinessSegment(MasterBase):
    __tablename__ = "business_segments"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(60), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(String(220))
    max_users: Mapped[int | None] = mapped_column(Integer)
    max_pdv_terminals: Mapped[int | None] = mapped_column(Integer)
    default_modules: Mapped[list[str]] = mapped_column(JSON, default=list)
    seller_role_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    technician_role_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.master_database import MasterBase


class CompanyBilling(MasterBase):
    __tablename__ = "company_billings"

    id: Mapped[int] = mapped_column(primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), index=True)
    reference_month: Mapped[str] = mapped_column(String(7), index=True)
    due_date: Mapped[date] = mapped_column(Date, index=True)
    amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    payment_method: Mapped[str | None] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    paid_amount: Mapped[float | None] = mapped_column(Numeric(12, 2))
    mercado_pago_payment_id: Mapped[str | None] = mapped_column(String(80), index=True)
    mercado_pago_status: Mapped[str | None] = mapped_column(String(40))
    mercado_pago_external_reference: Mapped[str | None] = mapped_column(String(120), index=True)
    mercado_pago_idempotency_key: Mapped[str | None] = mapped_column(String(80))
    pix_qr_code: Mapped[str | None] = mapped_column(Text)
    pix_qr_code_base64: Mapped[str | None] = mapped_column(Text)
    pix_ticket_url: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    company = relationship("Company")

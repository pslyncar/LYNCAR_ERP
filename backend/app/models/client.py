from datetime import datetime
from typing import Optional

from decimal import Decimal

from sqlalchemy import Boolean, DateTime, Integer, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Client(Base):
    __tablename__ = "clients"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(180), nullable=False)
    person_type: Mapped[str] = mapped_column(String(2), nullable=False, default="PF")
    trade_name: Mapped[Optional[str]] = mapped_column(String(180))
    document_number: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    state_registration: Mapped[Optional[str]] = mapped_column(String(40))
    municipal_registration: Mapped[Optional[str]] = mapped_column(String(40))
    tax_contributor_type: Mapped[Optional[str]] = mapped_column(String(20))
    city_code: Mapped[Optional[str]] = mapped_column(String(20))
    country_code: Mapped[Optional[str]] = mapped_column(String(4))
    country_name: Mapped[Optional[str]] = mapped_column(String(80))
    suframa: Mapped[Optional[str]] = mapped_column(String(20))
    contact_person: Mapped[Optional[str]] = mapped_column(String(150))
    phone: Mapped[Optional[str]] = mapped_column(String(40))
    mobile_phone: Mapped[Optional[str]] = mapped_column(String(40))
    email: Mapped[Optional[str]] = mapped_column(String(180))
    secondary_email: Mapped[Optional[str]] = mapped_column(String(180))
    address: Mapped[Optional[str]] = mapped_column(Text)
    address_number: Mapped[Optional[str]] = mapped_column(String(20))
    address_complement: Mapped[Optional[str]] = mapped_column(String(120))
    neighborhood: Mapped[Optional[str]] = mapped_column(String(120))
    city: Mapped[Optional[str]] = mapped_column(String(120))
    state: Mapped[Optional[str]] = mapped_column(String(2))
    zip_code: Mapped[Optional[str]] = mapped_column(String(20))
    contract_type: Mapped[str] = mapped_column(String(20), nullable=False, default="avulso")
    monthly_fee: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0"),
    )
    monthly_due_day: Mapped[Optional[int]] = mapped_column(Integer)
    allow_credit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    credit_limit: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
        default=Decimal("0"),
    )
    credit_status: Mapped[str] = mapped_column(
        String(30),
        nullable=False,
        default="liberado",
    )
    payment_terms: Mapped[Optional[str]] = mapped_column(String(80))
    billing_notes: Mapped[Optional[str]] = mapped_column(Text)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    equipments = relationship(
        "Equipment",
        back_populates="client",
        cascade="all, delete-orphan",
    )
    tickets = relationship(
        "Ticket",
        back_populates="client",
        cascade="all, delete-orphan",
    )
    service_orders = relationship(
        "ServiceOrder",
        back_populates="client",
        cascade="all, delete-orphan",
    )
    sales = relationship("Sale", back_populates="client")

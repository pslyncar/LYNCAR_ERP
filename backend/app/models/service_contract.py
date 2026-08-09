from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ServiceContract(Base):
    __tablename__ = "service_contracts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    client_id: Mapped[int] = mapped_column(ForeignKey("clients.id", ondelete="RESTRICT"), index=True)
    description: Mapped[str] = mapped_column(String(180), nullable=False)
    value_per_person: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    default_people_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    billing_periodicity: Mapped[str] = mapped_column(String(20), nullable=False, default="quinzenal")
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="active")
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    client = relationship("Client")
    rules = relationship(
        "ServiceContractAttendanceRule",
        back_populates="contract",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    consumption_items = relationship(
        "ServiceContractConsumptionItem",
        back_populates="contract",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    appointments = relationship("ServiceAppointment", back_populates="contract", lazy="selectin")
    billings = relationship("ServiceBilling", back_populates="contract", lazy="selectin")


class ServiceContractAttendanceRule(Base):
    __tablename__ = "service_contract_attendance_rules"
    __table_args__ = (UniqueConstraint("contract_id", "day_type", name="uq_service_contract_day_type"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    contract_id: Mapped[int] = mapped_column(ForeignKey("service_contracts.id", ondelete="CASCADE"), index=True)
    day_type: Mapped[str] = mapped_column(String(20), nullable=False)
    attends: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    charges: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    multiplier: Mapped[Decimal] = mapped_column(Numeric(8, 4), nullable=False, default=Decimal("1"))
    notes: Mapped[Optional[str]] = mapped_column(Text)

    contract = relationship("ServiceContract", back_populates="rules")


class ServiceContractConsumptionItem(Base):
    __tablename__ = "service_contract_consumption_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    contract_id: Mapped[int] = mapped_column(ForeignKey("service_contracts.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity_per_person: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    waste_percent: Mapped[Decimal] = mapped_column(Numeric(7, 2), nullable=False, default=Decimal("0"))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notes: Mapped[Optional[str]] = mapped_column(Text)

    contract = relationship("ServiceContract", back_populates="consumption_items")
    product = relationship("Product")


class ServiceAppointment(Base):
    __tablename__ = "service_appointments"
    __table_args__ = (UniqueConstraint("contract_id", "appointment_date", name="uq_service_appointment_date"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    contract_id: Mapped[int] = mapped_column(ForeignKey("service_contracts.id", ondelete="CASCADE"), index=True)
    appointment_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    day_type: Mapped[str] = mapped_column(String(20), nullable=False)
    people_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    value_per_person: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    multiplier: Mapped[Decimal] = mapped_column(Numeric(8, 4), nullable=False, default=Decimal("1"))
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="previsto")
    stock_posted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    stock_posted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    confirmed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    contract = relationship("ServiceContract", back_populates="appointments")
    items = relationship(
        "ServiceAppointmentConsumptionItem",
        back_populates="appointment",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class ServiceAppointmentConsumptionItem(Base):
    __tablename__ = "service_appointment_consumption_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    appointment_id: Mapped[int] = mapped_column(ForeignKey("service_appointments.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity_planned: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=Decimal("0"))
    quantity_confirmed: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False, default=Decimal("0"))
    unit: Mapped[str] = mapped_column(String(20), nullable=False, default="un")
    unit_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4))
    total_cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2))
    stock_movement_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stock_movements.id", ondelete="SET NULL"))
    notes: Mapped[Optional[str]] = mapped_column(Text)

    appointment = relationship("ServiceAppointment", back_populates="items")
    product = relationship("Product")
    stock_movement = relationship("StockMovement")


class ServiceBilling(Base):
    __tablename__ = "service_billings"
    __table_args__ = (UniqueConstraint("contract_id", "period_start", "period_end", name="uq_service_billing_period"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    number: Mapped[Optional[str]] = mapped_column(String(40), unique=True, index=True)
    contract_id: Mapped[int] = mapped_column(ForeignKey("service_contracts.id", ondelete="CASCADE"), index=True)
    receivable_id: Mapped[Optional[int]] = mapped_column(ForeignKey("receivables.id", ondelete="SET NULL"), index=True)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="generated")
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    notes: Mapped[Optional[str]] = mapped_column(Text)

    contract = relationship("ServiceContract", back_populates="billings")
    receivable = relationship("Receivable")
    items = relationship(
        "ServiceBillingItem",
        back_populates="billing",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class ServiceBillingItem(Base):
    __tablename__ = "service_billing_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    billing_id: Mapped[int] = mapped_column(ForeignKey("service_billings.id", ondelete="CASCADE"), index=True)
    appointment_id: Mapped[Optional[int]] = mapped_column(ForeignKey("service_appointments.id", ondelete="SET NULL"))
    item_date: Mapped[date] = mapped_column(Date, nullable=False)
    description: Mapped[str] = mapped_column(String(180), nullable=False)
    people_quantity: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    multiplier: Mapped[Decimal] = mapped_column(Numeric(8, 4), nullable=False)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    billing = relationship("ServiceBilling", back_populates="items")
    appointment = relationship("ServiceAppointment")

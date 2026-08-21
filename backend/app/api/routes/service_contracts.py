from datetime import date, datetime, time, timezone, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.models.client import Client
from app.models.product import Product
from app.models.receivable import Receivable
from app.models.service_contract import (
    ServiceAppointment,
    ServiceAppointmentConsumptionItem,
    ServiceBilling,
    ServiceBillingItem,
    ServiceContract,
    ServiceContractAttendanceRule,
    ServiceContractConsumptionItem,
)
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.service_contract import (
    GenerateAppointmentsPayload,
    ServiceAppointmentRead,
    ServiceAppointmentUpdate,
    ServiceBillingCreate,
    ServiceBillingRead,
    ServiceContractCreate,
    ServiceContractRead,
    ServiceContractUpdate,
)
from app.services.product_costs import apply_stock_in, apply_stock_out, base_unit_cost
from app.services.unit_conversion import convert_quantity
from app.services.holidays import ensure_holidays_for_period
from app.services.master_holidays import is_holiday

router = APIRouter()

DAY_TYPES = {"weekday", "saturday", "sunday", "holiday"}
CHARGED_STATUSES = {"previsto", "confirmado"}


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def contract_number(contract_id: int) -> str:
    return f"CT{contract_id}"


def appointment_number(appointment_id: int) -> str:
    return f"AP{appointment_id}"


def billing_number(billing_id: int) -> str:
    return f"FS{billing_id}"


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


def _validate_day_type(day_type: str) -> str:
    normalized = day_type.strip().lower()
    if normalized not in DAY_TYPES:
        raise HTTPException(status_code=422, detail="Tipo de dia invalido.")
    return normalized


def _calculate_total(
    people_quantity: Decimal,
    value_per_person: Decimal,
    multiplier: Decimal,
    *,
    charges: bool = True,
) -> Decimal:
    if not charges:
        return Decimal("0")
    return (people_quantity * value_per_person * multiplier).quantize(Decimal("0.01"))


def _last_day_of_month(year: int, month: int) -> date:
    if month == 12:
        return date(year + 1, 1, 1) - timedelta(days=1)
    return date(year, month + 1, 1) - timedelta(days=1)


def _next_quinzena(period_start: date, period_end: date) -> tuple[date, date]:
    if period_start.day <= 15 and period_end.day <= 15:
        next_start = date(period_start.year, period_start.month, 16)
        return next_start, _last_day_of_month(next_start.year, next_start.month)
    if period_start.month == 12:
        return date(period_start.year + 1, 1, 1), date(period_start.year + 1, 1, 15)
    return date(period_start.year, period_start.month + 1, 1), date(period_start.year, period_start.month + 1, 15)


def _read_contract(contract: ServiceContract) -> ServiceContractRead:
    data = ServiceContractRead.model_validate(contract)
    data.client_name = contract.client.name if contract.client else None
    for item_data, item in zip(data.consumption_items, contract.consumption_items):
        item_data.product_name = item.product.name if item.product else None
    return data


def _read_appointment(appointment: ServiceAppointment) -> ServiceAppointmentRead:
    data = ServiceAppointmentRead.model_validate(appointment)
    data.contract_number = appointment.contract.number if appointment.contract else None
    data.client_name = (
        appointment.contract.client.name
        if appointment.contract and appointment.contract.client
        else None
    )
    for item_data, item in zip(data.items, appointment.items):
        item_data.product_name = item.product.name if item.product else None
    return data


def _contract_query():
    return select(ServiceContract).options(
        selectinload(ServiceContract.client),
        selectinload(ServiceContract.rules),
        selectinload(ServiceContract.consumption_items).selectinload(
            ServiceContractConsumptionItem.product
        ),
    )


def _appointment_query():
    return select(ServiceAppointment).options(
        selectinload(ServiceAppointment.contract).selectinload(ServiceContract.client),
        selectinload(ServiceAppointment.items).selectinload(
            ServiceAppointmentConsumptionItem.product
        ),
    )


def get_contract_or_404(db: Session, contract_id: int) -> ServiceContract:
    contract = db.scalar(_contract_query().where(ServiceContract.id == contract_id))
    if contract is None:
        raise HTTPException(status_code=404, detail="Contrato nao encontrado.")
    return contract


def get_appointment_or_404(db: Session, appointment_id: int) -> ServiceAppointment:
    appointment = db.scalar(_appointment_query().where(ServiceAppointment.id == appointment_id))
    if appointment is None:
        raise HTTPException(status_code=404, detail="Apontamento nao encontrado.")
    return appointment


def get_billing_or_404(db: Session, contract_id: int, billing_id: int) -> ServiceBilling:
    billing = db.scalar(
        select(ServiceBilling)
        .options(
            selectinload(ServiceBilling.items).selectinload(ServiceBillingItem.appointment),
            selectinload(ServiceBilling.receivable).selectinload(Receivable.payments),
        )
        .where(
            ServiceBilling.id == billing_id,
            ServiceBilling.contract_id == contract_id,
        )
    )
    if billing is None:
        raise HTTPException(status_code=404, detail="Fechamento nao encontrado.")
    return billing


def _replace_contract_rules(contract: ServiceContract, rules_in) -> None:
    by_type = {rule.day_type: rule for rule in contract.rules}
    for day_type, attends, charges, multiplier in (
        ("weekday", True, True, Decimal("1")),
        ("saturday", False, False, Decimal("0")),
        ("sunday", False, False, Decimal("0")),
        ("holiday", False, False, Decimal("0")),
    ):
        if day_type not in by_type:
            contract.rules.append(
                ServiceContractAttendanceRule(
                    day_type=day_type,
                    attends=attends,
                    charges=charges,
                    multiplier=multiplier,
                )
            )
    if rules_in is None:
        return
    by_type = {rule.day_type: rule for rule in contract.rules}
    for rule_in in rules_in:
        day_type = _validate_day_type(rule_in.day_type)
        rule = by_type.get(day_type)
        if rule is None:
            rule = ServiceContractAttendanceRule(day_type=day_type)
            contract.rules.append(rule)
        rule.attends = rule_in.attends
        rule.charges = rule_in.charges
        rule.multiplier = rule_in.multiplier
        rule.notes = rule_in.notes


def _replace_contract_items(contract: ServiceContract, items_in) -> None:
    if items_in is None:
        return
    contract.consumption_items.clear()
    for item_in in items_in:
        contract.consumption_items.append(
            ServiceContractConsumptionItem(
                product_id=item_in.product_id,
                quantity_per_person=item_in.quantity_per_person,
                unit=item_in.unit.strip() or "un",
                waste_percent=item_in.waste_percent,
                active=item_in.active,
                notes=item_in.notes,
            )
        )


def _day_type_for(db: Session, target_date: date, client: Client | None) -> str:
    _ = db
    city = client.city.strip() if client and client.city else None
    city_code = getattr(client, "city_code", None)
    state = client.state.strip().upper() if client and client.state else None
    with MasterSessionLocal() as master_db:
        if is_holiday(
            master_db,
            target_date,
            city=city,
            city_code=city_code,
            state=state,
        ):
            master_db.commit()
            return "holiday"
        master_db.commit()
    if target_date.weekday() == 5:
        return "saturday"
    if target_date.weekday() == 6:
        return "sunday"
    return "weekday"


def _rule_for(contract: ServiceContract, day_type: str) -> ServiceContractAttendanceRule:
    for rule in contract.rules:
        if rule.day_type == day_type:
            return rule
    fallback = ServiceContractAttendanceRule(
        day_type=day_type,
        attends=day_type == "weekday",
        charges=day_type == "weekday",
        multiplier=Decimal("1") if day_type == "weekday" else Decimal("0"),
    )
    contract.rules.append(fallback)
    return fallback


def _build_consumption_items(contract: ServiceContract, people_quantity: Decimal) -> list[ServiceAppointmentConsumptionItem]:
    items: list[ServiceAppointmentConsumptionItem] = []
    for item in contract.consumption_items:
        if not item.active:
            continue
        quantity = item.quantity_per_person * people_quantity * (
            Decimal("1") + (item.waste_percent / Decimal("100"))
        )
        items.append(
            ServiceAppointmentConsumptionItem(
                product_id=item.product_id,
                quantity_planned=quantity,
                quantity_confirmed=quantity,
                unit=item.unit,
                notes=item.notes,
            )
        )
    return items


def _ensure_appointment_for_date(db: Session, contract: ServiceContract, target_date: date) -> ServiceAppointment:
    appointment = db.scalar(
        select(ServiceAppointment).where(
            ServiceAppointment.contract_id == contract.id,
            ServiceAppointment.appointment_date == target_date,
        )
    )
    if appointment is not None:
        _sync_existing_appointment_calendar(db, contract, appointment)
        return appointment
    day_type = _day_type_for(db, target_date, contract.client)
    rule = _rule_for(contract, day_type)
    billable = rule.attends and rule.charges and rule.multiplier > 0
    status_value = "previsto" if billable else "sem_atendimento"
    total = _calculate_total(
        contract.default_people_quantity,
        contract.value_per_person,
        rule.multiplier,
        charges=billable,
    )
    appointment = ServiceAppointment(
        contract_id=contract.id,
        appointment_date=target_date,
        day_type=day_type,
        people_quantity=contract.default_people_quantity if billable else Decimal("0"),
        value_per_person=contract.value_per_person,
        multiplier=rule.multiplier,
        total_amount=total,
        status=status_value,
    )
    if billable:
        appointment.items = _build_consumption_items(contract, contract.default_people_quantity)
    db.add(appointment)
    return appointment


def _sync_existing_appointment_calendar(
    db: Session,
    contract: ServiceContract,
    appointment: ServiceAppointment,
) -> None:
    if appointment.stock_posted or appointment.status == "confirmado":
        return
    if appointment.id is not None and _appointment_is_billed(db, appointment.id):
        return
    day_type = _day_type_for(db, appointment.appointment_date, contract.client)
    rule = _rule_for(contract, day_type)
    billable = rule.attends and rule.charges and rule.multiplier > 0
    expected_status = "previsto" if billable else "sem_atendimento"
    people_quantity = contract.default_people_quantity if billable else Decimal("0")
    total = _calculate_total(
        people_quantity,
        contract.value_per_person,
        rule.multiplier,
        charges=billable,
    )
    if (
        appointment.day_type == day_type
        and appointment.status == expected_status
        and appointment.people_quantity == people_quantity
        and appointment.value_per_person == contract.value_per_person
        and appointment.multiplier == rule.multiplier
        and appointment.total_amount == total
    ):
        return
    appointment.day_type = day_type
    appointment.status = expected_status
    appointment.people_quantity = people_quantity
    appointment.value_per_person = contract.value_per_person
    appointment.multiplier = rule.multiplier
    appointment.total_amount = total
    appointment.items.clear()
    if billable:
        appointment.items = _build_consumption_items(contract, people_quantity)


def _replace_appointment_items(
    db: Session,
    appointment: ServiceAppointment,
    items_in,
    user: User,
) -> None:
    if items_in is None:
        return
    if appointment.stock_posted:
        _reverse_stock_for_appointment(
            db,
            appointment,
            user,
            "Estorno automatico para edicao dos produtos do apontamento.",
        )
    appointment.items.clear()
    for item_in in items_in:
        appointment.items.append(
            ServiceAppointmentConsumptionItem(
                product_id=item_in.product_id,
                quantity_planned=item_in.quantity_planned,
                quantity_confirmed=item_in.quantity_confirmed,
                unit=item_in.unit.strip() or "un",
                notes=item_in.notes,
            )
        )


def _post_stock_for_appointment(db: Session, appointment: ServiceAppointment, user: User) -> None:
    if appointment.stock_posted:
        return
    for item in appointment.items:
        product = db.get(Product, item.product_id)
        if product is None:
            raise HTTPException(status_code=404, detail="Produto do apontamento nao encontrado.")
        try:
            quantity = convert_quantity(item.quantity_confirmed, item.unit, product.unit)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if quantity <= 0:
            continue
        before = product.stock_quantity
        unit_cost, total_cost = apply_stock_out(product, quantity)
        stock_warning = (
            f" Estoque ficou negativo: antes {before} {product.unit}, "
            f"baixa {quantity} {product.unit}, depois {product.stock_quantity} {product.unit}."
            if product.stock_quantity < 0
            else ""
        )
        movement = StockMovement(
            product_id=product.id,
            user_id=user.id,
            movement_type="service_consumption",
            source_type="service_appointment",
            source_id=appointment.id,
            source_number=appointment_number(appointment.id),
            quantity_delta=-quantity,
            quantity_before=before,
            quantity_after=product.stock_quantity,
            unit=product.unit,
            unit_price=unit_cost,
            total_value=total_cost,
            reason="Consumo por contrato variavel",
            notes=f"Baixa do apontamento {appointment_number(appointment.id)}.{stock_warning}",
        )
        db.add(movement)
        db.flush()
        item.unit_cost = unit_cost
        item.total_cost = total_cost
        item.stock_movement_id = movement.id
    appointment.stock_posted = True
    appointment.stock_posted_at = now_utc()


def _reverse_stock_for_appointment(db: Session, appointment: ServiceAppointment, user: User, reason: str) -> None:
    if not appointment.stock_posted:
        return
    for item in appointment.items:
        product = db.get(Product, item.product_id)
        if product is None:
            continue
        try:
            quantity = convert_quantity(item.quantity_confirmed, item.unit, product.unit)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if quantity <= 0:
            continue
        before = product.stock_quantity
        unit_cost_snapshot = base_unit_cost(product)
        total_cost = (
            item.total_cost
            if item.total_cost is not None
            else quantity * unit_cost_snapshot
            if unit_cost_snapshot is not None
            else None
        )
        unit_cost, total_value = apply_stock_in(product, quantity, total_cost)
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=user.id,
                movement_type="service_consumption_return",
                source_type="service_appointment",
                source_id=appointment.id,
                source_number=appointment_number(appointment.id),
                quantity_delta=quantity,
                quantity_before=before,
                quantity_after=product.stock_quantity,
                unit=product.unit,
                unit_price=unit_cost,
                total_value=total_value,
                reason="Estorno de consumo por contrato variavel",
                notes=reason,
            )
        )
    appointment.stock_posted = False
    appointment.stock_posted_at = None


def _appointment_is_billed(db: Session, appointment_id: int) -> bool:
    return (
        db.scalar(
            select(ServiceBillingItem.id)
            .join(ServiceBilling, ServiceBilling.id == ServiceBillingItem.billing_id)
            .where(
                ServiceBillingItem.appointment_id == appointment_id,
                ServiceBilling.status != "cancelado",
            )
            .limit(1)
        )
        is not None
    )


def _ensure_appointment_not_billed(db: Session, appointment: ServiceAppointment) -> None:
    if _appointment_is_billed(db, appointment.id):
        raise HTTPException(
            status_code=409,
            detail="Este apontamento ja entrou em um fechamento. Cancele/reabra o fechamento antes de alterar.",
        )


def _confirm_appointment_for_billing(
    db: Session,
    appointment: ServiceAppointment,
    user: User,
) -> None:
    if appointment.status in {"cancelado", "sem_atendimento"}:
        return
    if appointment.total_amount <= 0:
        return
    _post_stock_for_appointment(db, appointment, user)
    appointment.status = "confirmado"
    appointment.confirmed_at = appointment.confirmed_at or now_utc()
    appointment.total_amount = _calculate_total(
        appointment.people_quantity,
        appointment.value_per_person,
        appointment.multiplier,
        charges=True,
    )


@router.get("", response_model=list[ServiceContractRead])
def list_contracts(
    client_id: int | None = None,
    status_filter: str | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("service_contracts:view", "service_contracts:manage")),
) -> list[ServiceContractRead]:
    query = _contract_query().order_by(ServiceContract.id.desc())
    if client_id is not None:
        query = query.where(ServiceContract.client_id == client_id)
    if status_filter:
        query = query.where(ServiceContract.status == status_filter)
    return [_read_contract(contract) for contract in db.scalars(query).all()]


@router.post("", response_model=ServiceContractRead, status_code=status.HTTP_201_CREATED)
def create_contract(
    contract_in: ServiceContractCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("service_contracts:manage")),
) -> ServiceContractRead:
    if db.get(Client, contract_in.client_id) is None:
        raise HTTPException(status_code=404, detail="Cliente nao encontrado.")
    contract = ServiceContract(
        client_id=contract_in.client_id,
        description=contract_in.description.strip(),
        value_per_person=contract_in.value_per_person,
        default_people_quantity=contract_in.default_people_quantity,
        billing_periodicity=contract_in.billing_periodicity,
        start_date=contract_in.start_date,
        status=contract_in.status,
        active=contract_in.active,
        notes=contract_in.notes,
    )
    _replace_contract_rules(contract, contract_in.rules)
    _replace_contract_items(contract, contract_in.consumption_items)
    db.add(contract)
    db.flush()
    contract.number = contract_number(contract.id)
    db.commit()
    return _read_contract(get_contract_or_404(db, contract.id))


@router.put("/{contract_id}", response_model=ServiceContractRead)
def update_contract(
    contract_id: int,
    contract_in: ServiceContractUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("service_contracts:manage")),
) -> ServiceContractRead:
    contract = get_contract_or_404(db, contract_id)
    data = contract_in.model_dump(exclude_unset=True, exclude={"rules", "consumption_items"})
    if "client_id" in data and db.get(Client, data["client_id"]) is None:
        raise HTTPException(status_code=404, detail="Cliente nao encontrado.")
    for field, value in data.items():
        if value is None and field != "notes":
            continue
        setattr(contract, field, value.strip() if field == "description" else value)
    _replace_contract_rules(contract, contract_in.rules)
    _replace_contract_items(contract, contract_in.consumption_items)
    db.commit()
    return _read_contract(get_contract_or_404(db, contract.id))


@router.post("/{contract_id}/appointments/generate", response_model=list[ServiceAppointmentRead])
def generate_appointments(
    contract_id: int,
    payload: GenerateAppointmentsPayload,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("service_contracts:appointments")),
) -> list[ServiceAppointmentRead]:
    if payload.period_end < payload.period_start:
        raise HTTPException(status_code=422, detail="Periodo final menor que o inicial.")
    contract = get_contract_or_404(db, contract_id)
    ensure_holidays_for_period(db, contract.client, payload.period_start, payload.period_end)
    existing_billing = db.scalar(
        select(ServiceBilling.id).where(
            ServiceBilling.contract_id == contract_id,
            ServiceBilling.period_start == payload.period_start,
            ServiceBilling.period_end == payload.period_end,
            ServiceBilling.status != "cancelado",
        )
    )
    if existing_billing is not None:
        raise HTTPException(
            status_code=409,
            detail="Este periodo ja foi fechado. Use o Historico para cancelar/reabrir antes de corrigir.",
        )
    existing_appointment = db.scalar(
        select(ServiceAppointment.id).where(
            ServiceAppointment.contract_id == contract_id,
            ServiceAppointment.appointment_date >= payload.period_start,
            ServiceAppointment.appointment_date <= payload.period_end,
        ).limit(1)
    )
    if existing_appointment is not None:
        raise HTTPException(
            status_code=409,
            detail="Este periodo ja foi gerado para este contrato. Use Buscar para carregar os dias existentes.",
        )
    created_or_existing: list[ServiceAppointment] = []
    current = payload.period_start
    while current <= payload.period_end:
        created_or_existing.append(_ensure_appointment_for_date(db, contract, current))
        current += timedelta(days=1)
    db.commit()
    appointments = list(
        db.scalars(
            _appointment_query()
            .where(
                ServiceAppointment.contract_id == contract_id,
                ServiceAppointment.appointment_date >= payload.period_start,
                ServiceAppointment.appointment_date <= payload.period_end,
            )
            .order_by(ServiceAppointment.appointment_date)
        ).all()
    )
    return [_read_appointment(appointment) for appointment in appointments]


@router.get("/{contract_id}/appointments", response_model=list[ServiceAppointmentRead])
def list_appointments(
    contract_id: int,
    period_start: date | None = None,
    period_end: date | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("service_contracts:view", "service_contracts:appointments")),
) -> list[ServiceAppointmentRead]:
    contract = get_contract_or_404(db, contract_id)
    if period_start is not None and period_end is not None:
        ensure_holidays_for_period(db, contract.client, period_start, period_end)
    query = _appointment_query().where(ServiceAppointment.contract_id == contract_id)
    if period_start is not None:
        query = query.where(ServiceAppointment.appointment_date >= period_start)
    if period_end is not None:
        query = query.where(ServiceAppointment.appointment_date <= period_end)
    appointments = list(db.scalars(query.order_by(ServiceAppointment.appointment_date)).all())
    for appointment in appointments:
        _sync_existing_appointment_calendar(db, contract, appointment)
    db.commit()
    appointments = list(db.scalars(query.order_by(ServiceAppointment.appointment_date)).all())
    return [_read_appointment(appointment) for appointment in appointments]


@router.put("/appointments/{appointment_id}", response_model=ServiceAppointmentRead)
def update_appointment(
    appointment_id: int,
    appointment_in: ServiceAppointmentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_contracts:appointments")),
) -> ServiceAppointmentRead:
    appointment = get_appointment_or_404(db, appointment_id)
    _ensure_appointment_not_billed(db, appointment)
    if appointment.stock_posted and appointment_in.status in {"cancelado", "sem_atendimento"}:
        _reverse_stock_for_appointment(
            db,
            appointment,
            current_user,
            "Estorno automatico por alteracao de status do apontamento.",
        )
    data = appointment_in.model_dump(exclude_unset=True, exclude={"items"})
    if "day_type" in data and data["day_type"] is not None:
        data["day_type"] = _validate_day_type(data["day_type"])
    for field, value in data.items():
        if value is None and field != "notes":
            continue
        setattr(appointment, field, value)
    charges = appointment.status not in {"cancelado", "sem_atendimento"}
    appointment.total_amount = _calculate_total(
        appointment.people_quantity,
        appointment.value_per_person,
        appointment.multiplier,
        charges=charges,
    )
    _replace_appointment_items(db, appointment, appointment_in.items, current_user)
    db.commit()
    return _read_appointment(get_appointment_or_404(db, appointment.id))


@router.post("/appointments/{appointment_id}/confirm", response_model=ServiceAppointmentRead)
def confirm_appointment(
    appointment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_contracts:appointments")),
) -> ServiceAppointmentRead:
    appointment = get_appointment_or_404(db, appointment_id)
    _ensure_appointment_not_billed(db, appointment)
    if appointment.status == "sem_atendimento":
        raise HTTPException(status_code=400, detail="Dia sem atendimento nao pode ser confirmado.")
    if appointment.status == "cancelado":
        raise HTTPException(status_code=400, detail="Apontamento cancelado nao pode ser confirmado.")
    _post_stock_for_appointment(db, appointment, current_user)
    appointment.status = "confirmado"
    appointment.confirmed_at = now_utc()
    appointment.total_amount = _calculate_total(
        appointment.people_quantity,
        appointment.value_per_person,
        appointment.multiplier,
        charges=True,
    )
    db.commit()
    return _read_appointment(get_appointment_or_404(db, appointment.id))


@router.post("/appointments/{appointment_id}/cancel", response_model=ServiceAppointmentRead)
def cancel_appointment(
    appointment_id: int,
    reason: str = Query(default="Cancelamento do apontamento"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_contracts:appointments")),
) -> ServiceAppointmentRead:
    appointment = get_appointment_or_404(db, appointment_id)
    _ensure_appointment_not_billed(db, appointment)
    _reverse_stock_for_appointment(db, appointment, current_user, reason)
    appointment.status = "cancelado"
    appointment.total_amount = Decimal("0")
    appointment.notes = "\n".join(part for part in [appointment.notes, reason] if part)
    db.commit()
    return _read_appointment(get_appointment_or_404(db, appointment.id))


@router.post("/{contract_id}/billings", response_model=ServiceBillingRead, status_code=status.HTTP_201_CREATED)
def create_billing(
    contract_id: int,
    payload: ServiceBillingCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_contracts:billing")),
) -> ServiceBilling:
    if payload.period_end < payload.period_start:
        raise HTTPException(status_code=422, detail="Periodo final menor que o inicial.")
    contract = get_contract_or_404(db, contract_id)
    ensure_holidays_for_period(db, contract.client, payload.period_start, payload.period_end)
    existing = db.scalar(
        select(ServiceBilling).where(
            ServiceBilling.contract_id == contract_id,
            ServiceBilling.period_start == payload.period_start,
            ServiceBilling.period_end == payload.period_end,
            ServiceBilling.status != "cancelado",
        )
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Ja existe fechamento para este periodo.")
    current = payload.period_start
    while current <= payload.period_end:
        _ensure_appointment_for_date(db, contract, current)
        current += timedelta(days=1)
    db.flush()
    period_appointments = list(
        db.scalars(
            _appointment_query().where(
                ServiceAppointment.contract_id == contract_id,
                ServiceAppointment.appointment_date >= payload.period_start,
                ServiceAppointment.appointment_date <= payload.period_end,
            )
        ).all()
    )
    for appointment in period_appointments:
        _confirm_appointment_for_billing(db, appointment, current_user)
    db.flush()
    appointments = [
        appointment
        for appointment in period_appointments
        if appointment.status in CHARGED_STATUSES and appointment.total_amount > 0
    ]
    total = sum((appointment.total_amount for appointment in appointments), Decimal("0")).quantize(Decimal("0.01"))
    billing = ServiceBilling(
        contract_id=contract_id,
        period_start=payload.period_start,
        period_end=payload.period_end,
        total_amount=total,
        notes=payload.notes,
    )
    db.add(billing)
    db.flush()
    billing.number = billing_number(billing.id)
    for appointment in sorted(appointments, key=lambda item: item.appointment_date):
        billing.items.append(
            ServiceBillingItem(
                appointment_id=appointment.id,
                item_date=appointment.appointment_date,
                description=f"Atendimento {appointment.appointment_date.strftime('%d/%m/%Y')}",
                people_quantity=appointment.people_quantity,
                unit_price=appointment.value_per_person,
                multiplier=appointment.multiplier,
                total_amount=appointment.total_amount,
            )
        )
    due = payload.due_date or payload.period_end
    receivable = Receivable(
        client_id=contract.client_id,
        description=f"{billing.number} - {contract.description}",
        original_amount=total,
        paid_amount=Decimal("0"),
        balance_amount=total,
        status="open" if total > 0 else "paid",
        due_date=datetime.combine(due, time.min),
        notes=f"Faturamento variavel de {payload.period_start} a {payload.period_end}.",
        entry_type="service",
    )
    db.add(receivable)
    db.flush()
    receivable.number = receivable_number(receivable.id)
    billing.receivable_id = receivable.id
    next_start, next_end = _next_quinzena(payload.period_start, payload.period_end)
    current = next_start
    while current <= next_end:
        _ensure_appointment_for_date(db, contract, current)
        current += timedelta(days=1)
    db.commit()
    return db.scalar(
        select(ServiceBilling)
        .options(selectinload(ServiceBilling.items), selectinload(ServiceBilling.receivable))
        .where(ServiceBilling.id == billing.id)
    )


@router.get("/{contract_id}/billings", response_model=list[ServiceBillingRead])
def list_billings(
    contract_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permission("service_contracts:view", "service_contracts:billing")),
) -> list[ServiceBilling]:
    get_contract_or_404(db, contract_id)
    return list(
        db.scalars(
            select(ServiceBilling)
            .options(selectinload(ServiceBilling.items))
            .where(ServiceBilling.contract_id == contract_id)
            .order_by(ServiceBilling.period_start.desc())
        ).all()
    )


@router.post("/{contract_id}/billings/{billing_id}/cancel", response_model=ServiceBillingRead)
def cancel_billing(
    contract_id: int,
    billing_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("service_contracts:billing")),
) -> ServiceBilling:
    billing = get_billing_or_404(db, contract_id, billing_id)
    if billing.status == "cancelado":
        return billing
    receivable = billing.receivable
    if receivable is not None and (receivable.paid_amount > 0 or receivable.payments):
        raise HTTPException(
            status_code=409,
            detail="Este fechamento tem recebimento lançado. Estorne a baixa no financeiro antes de cancelar.",
        )
    for item in billing.items:
        appointment = item.appointment
        if appointment is None:
            continue
        _reverse_stock_for_appointment(
            db,
            appointment,
            current_user,
            f"Cancelamento do fechamento {billing.number or billing.id}.",
        )
        appointment.status = "previsto" if appointment.total_amount > 0 else "sem_atendimento"
        appointment.confirmed_at = None
    if receivable is not None:
        db.delete(receivable)
        billing.receivable_id = None
    billing.status = "cancelado"
    billing.notes = "\n".join(
        part
        for part in [
            billing.notes,
            f"Cancelado/reaberto em {now_utc().isoformat()} para edicao.",
        ]
        if part
    )
    db.commit()
    return get_billing_or_404(db, contract_id, billing_id)


@router.post("/{contract_id}/billings/{billing_id}/reopen", status_code=status.HTTP_204_NO_CONTENT)
def reopen_canceled_billing(
    contract_id: int,
    billing_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("service_contracts:billing")),
) -> None:
    billing = get_billing_or_404(db, contract_id, billing_id)
    if billing.status != "cancelado":
        raise HTTPException(status_code=409, detail="Somente fechamentos cancelados podem ser reabertos.")
    if billing.receivable_id is not None:
        raise HTTPException(status_code=409, detail="Este fechamento ainda possui Contas a Receber vinculado.")
    db.delete(billing)
    db.commit()
    return None

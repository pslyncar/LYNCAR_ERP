from datetime import date, datetime, time
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import bearer_scheme, require_any_permission, require_permission
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.cash_closing import CashClosing, CashClosingMovement, CashClosingPayment
from app.models.client import Client
from app.models.company import Company
from app.models.pdv_cash_session import PdvCashSession
from app.models.product import Product
from app.models.receivable import Receivable
from app.models.sale import Sale, SaleItem, SalePayment
from app.models.service_order import ServiceOrder, ServiceOrderEvent
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.sale import (
    SaleCreate,
    SalePaymentsUpdate,
    SaleRead,
    SaleSellerRead,
    SalesSettings,
)
from app.services.access_control import user_has_configured_permission
from app.services.product_batches import apply_batch_out, return_to_batch
from app.services.product_costs import apply_stock_in, apply_stock_out
from app.services.pdv_pricing import effective_product_sale_price

router = APIRouter()

MONEY_QUANT = Decimal("0.01")
MONEY_TOLERANCE = Decimal("0.01")
FINANCIAL_PAYMENT_METHODS = {"boleto", "crediario"}
DEFAULT_MAX_DISCOUNT_PERCENT = Decimal("100.00")


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def percent(value: Decimal | int | float | str | None) -> Decimal:
    if value is None:
        return DEFAULT_MAX_DISCOUNT_PERCENT
    normalized = Decimal(str(value)).quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
    return max(Decimal("0.00"), min(DEFAULT_MAX_DISCOUNT_PERCENT, normalized))


def _tenant_company_code(
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token ausente.")
    payload = decode_access_token(credentials.credentials)
    company_code = payload.get("company_code")
    if not isinstance(company_code, str) or not company_code.strip():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Empresa invalida.")
    return company_code.strip()


def _sales_settings_for_company(company_code: str) -> SalesSettings:
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa nao encontrada.")
        return SalesSettings(
            max_discount_percent=percent(company.sales_max_discount_percent)
        )


def sale_number(sale_id: int) -> str:
    return f"V{sale_id}"


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


def service_order_id_from_sale(sale: Sale) -> int | None:
    marker = (sale.offline_client_id or "").strip()
    if sale.source != "os" or not marker.startswith("os:"):
        return None
    try:
        return int(marker.split(":", 1)[1])
    except ValueError:
        return None


def sync_service_order_status_from_sale(
    db: Session,
    sale: Sale,
    has_financial_receivable: bool,
    current_user: User,
) -> None:
    service_order_id = service_order_id_from_sale(sale)
    if service_order_id is None:
        return
    service_order = db.get(ServiceOrder, service_order_id)
    if service_order is None:
        return
    previous_status = service_order.status
    service_order.status = "aguardando_retirada" if has_financial_receivable else "concluida"
    service_order.sold_by_user_id = sale.seller_user_id
    if service_order.status == "concluida" and service_order.closed_at is None:
        service_order.closed_at = datetime.utcnow()
    if service_order.status != "concluida":
        service_order.closed_at = None
    db.add(
        ServiceOrderEvent(
            service_order_id=service_order.id,
            user_id=current_user.id,
            event_type="sale_created",
            status_from=previous_status,
            status_to=service_order.status,
            assigned_user_id=service_order.assigned_user_id,
            notes=f"Venda {sale.number or sale.id} gerada para a OS.",
        )
    )


@router.get("/settings", response_model=SalesSettings)
def get_sales_settings(
    current_user: User = Depends(
        require_any_permission("sales:view", "sales:manual", "sales:create")
    ),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> SalesSettings:
    return _sales_settings_for_company(_tenant_company_code(credentials))


@router.put("/settings", response_model=SalesSettings)
def update_sales_settings(
    payload: SalesSettings,
    current_user: User = Depends(require_permission("permissions:manage")),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> SalesSettings:
    company_code = _tenant_company_code(credentials)
    max_discount_percent = percent(payload.max_discount_percent)
    with MasterSessionLocal() as master_db:
        company = master_db.scalar(select(Company).where(Company.code == company_code))
        if company is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa nao encontrada.")
        company.sales_max_discount_percent = max_discount_percent
        master_db.commit()
    return SalesSettings(max_discount_percent=max_discount_percent)


def is_financial_payment(method: str) -> bool:
    return method in FINANCIAL_PAYMENT_METHODS


def financial_description(methods: set[str], sale_number_value: str | None) -> str:
    number = sale_number_value or "sem numero"
    if methods == {"boleto"}:
        return f"Boleto da venda {number}"
    if methods == {"crediario"}:
        return f"Crediario da venda {number}"
    return f"Financeiro da venda {number}"


def cash_closing_number(closing_id: int) -> str:
    return f"CX{closing_id}"


def get_sale_or_404(db: Session, sale_id: int) -> Sale:
    sale = db.scalar(
        select(Sale)
        .options(
            selectinload(Sale.items),
            selectinload(Sale.payments),
            selectinload(Sale.seller),
            selectinload(Sale.fiscal_documents),
        )
        .where(Sale.id == sale_id)
    )
    if sale is None:
        raise HTTPException(status_code=404, detail="Venda não encontrada.")
    return sale


def cancel_sale_receivables(
    db: Session,
    sale: Sale,
    current_user: User,
    reason: str,
) -> None:
    receivables = list(
        db.scalars(select(Receivable).where(Receivable.sale_id == sale.id)).all()
    )
    for receivable in receivables:
        if receivable.status == "canceled":
            continue
        receivable.status = "canceled"
        receivable.balance_amount = Decimal("0")
        receivable.settled_at = datetime.utcnow()
        note = reason
        if current_user.name:
            note = f"{note} Usuario: {current_user.name}."
        receivable.notes = (
            f"{receivable.notes}\n{note}" if receivable.notes else note
        )


def sync_sale_financial_receivable(
    db: Session,
    sale: Sale,
    current_user: User,
) -> None:
    financial_payments = [
        payment for payment in sale.payments if is_financial_payment(payment.method)
    ]
    financial_amount = money(
        sum(
            (payment.amount for payment in financial_payments),
            Decimal("0"),
        )
    )
    financial_methods = {payment.method for payment in financial_payments}
    receivables = list(
        db.scalars(select(Receivable).where(Receivable.sale_id == sale.id)).all()
    )
    active = next(
        (item for item in receivables if item.status != "canceled"),
        None,
    )
    if financial_amount <= 0:
        cancel_sale_receivables(
            db,
            sale,
            current_user,
            "Financeiro cancelado automaticamente por alteracao da forma de pagamento da venda.",
        )
        return
    if sale.client_id is None:
        raise HTTPException(
            status_code=400,
            detail="Pagamento boleto/crediario precisa ter cliente selecionado na venda.",
        )
    client = db.get(Client, sale.client_id)
    if client is None or not client.active:
        raise HTTPException(status_code=400, detail="Cliente do financeiro nao encontrado ou inativo.")
    if "crediario" in financial_methods and (
        not client.allow_credit or client.credit_status != "liberado"
    ):
        raise HTTPException(status_code=400, detail="Cliente não está liberado para crediário.")
    if active is None:
        receivable = Receivable(
            sale_id=sale.id,
            client_id=sale.client_id,
            description=financial_description(financial_methods, sale.number),
            original_amount=financial_amount,
            paid_amount=Decimal("0"),
            balance_amount=financial_amount,
            status="open",
            notes="Gerado automaticamente por alteracao da forma de pagamento da venda.",
            entry_type="sale",
        )
        db.add(receivable)
        db.flush()
        receivable.number = receivable_number(receivable.id)
        return
    paid_amount = active.paid_amount or Decimal("0")
    active.description = financial_description(financial_methods, sale.number)
    active.original_amount = financial_amount
    active.balance_amount = max(Decimal("0"), financial_amount - paid_amount)
    if active.balance_amount <= 0:
        active.balance_amount = Decimal("0")
        active.status = "paid"
        active.settled_at = datetime.utcnow()
    elif paid_amount > 0:
        active.status = "partial"
        active.settled_at = None
    else:
        active.status = "open"
        active.settled_at = None
    active.notes = (
        f"{active.notes}\nValor atualizado por alteracao da forma de pagamento da venda."
        if active.notes
        else "Valor atualizado por alteracao da forma de pagamento da venda."
    )


def create_administrative_cash_control(
    db: Session,
    sale: Sale,
    current_user: User,
) -> None:
    if sale.source != "venda" or sale.status != "finalizada":
        return
    received_payments = [
        payment for payment in sale.payments if not is_financial_payment(payment.method)
    ]
    if not received_payments:
        return
    sold_at = sale.sold_at or datetime.utcnow()
    date_key = sold_at.date().isoformat()
    change_amount = sale.change_amount or Decimal("0")
    cash_amount = max(
        Decimal("0"),
        sum(
            (payment.amount for payment in received_payments if payment.method == "dinheiro"),
            Decimal("0"),
        )
        - change_amount,
    )
    received_amount = max(
        Decimal("0"),
        sum((payment.amount for payment in received_payments), Decimal("0")) - change_amount,
    )
    batch_note = f"Controle automatico das vendas administrativas {date_key}."
    closing = db.scalar(
        select(CashClosing)
        .options(selectinload(CashClosing.payments), selectinload(CashClosing.movements))
        .where(
            CashClosing.notes == batch_note,
            CashClosing.status == "pending_treasury",
        )
    )
    if closing is None:
        closing = CashClosing(
            operator_name="Vendas administrativas",
            opened_at=sold_at,
            opened_by_user_id=current_user.id,
            closed_by_user_id=current_user.id,
            opening_amount=Decimal("0"),
            expected_cash_amount=Decimal("0"),
            counted_cash_amount=Decimal("0"),
            cash_difference_amount=Decimal("0"),
            total_sales_amount=Decimal("0"),
            total_sales_count=0,
            total_withdrawal_amount=Decimal("0"),
            total_supply_amount=Decimal("0"),
            status="pending_treasury",
            notes=batch_note,
        )
        db.add(closing)
        db.flush()
        closing.number = cash_closing_number(closing.id)

    closing.closed_by_user_id = current_user.id
    closing.closed_at = sold_at
    closing.expected_cash_amount += cash_amount
    closing.counted_cash_amount += cash_amount
    closing.cash_difference_amount = closing.counted_cash_amount - closing.expected_cash_amount
    closing.total_sales_amount += received_amount
    closing.total_sales_count += 1
    remaining_change = change_amount
    for payment in received_payments:
        payment_amount = payment.amount
        if payment.method == "dinheiro" and remaining_change > 0:
            change_applied = min(payment_amount, remaining_change)
            payment_amount -= change_applied
            remaining_change -= change_applied
        existing_payment = next(
            (item for item in closing.payments if item.method == payment.method),
            None,
        )
        if existing_payment is None:
            closing.payments.append(
                CashClosingPayment(method=payment.method, amount=payment_amount)
            )
        else:
            existing_payment.amount += payment_amount
    closing.movements.append(
        CashClosingMovement(
            movement_type="venda_administrativa",
            amount=received_amount,
            reason=f"Venda {sale.number}",
            created_at=sold_at,
        )
    )


def mark_administrative_cash_control_canceled(
    db: Session,
    sale: Sale,
) -> None:
    if sale.source != "venda" or sale.number is None:
        return
    closing = db.scalar(
        select(CashClosing)
        .options(selectinload(CashClosing.payments), selectinload(CashClosing.movements))
        .where(CashClosing.movements.any(CashClosingMovement.reason == f"Venda {sale.number}"))
    )
    if closing is None:
        return
    received_payments = [
        payment for payment in sale.payments if not is_financial_payment(payment.method)
    ]
    if not received_payments:
        return
    change_amount = sale.change_amount or Decimal("0")
    received_amount = max(
        Decimal("0"),
        sum((payment.amount for payment in received_payments), Decimal("0")) - change_amount,
    )
    cash_amount = max(
        Decimal("0"),
        sum(
            (payment.amount for payment in received_payments if payment.method == "dinheiro"),
            Decimal("0"),
        )
        - change_amount,
    )
    if closing.status == "pending_treasury":
        closing.expected_cash_amount = max(
            Decimal("0"),
            closing.expected_cash_amount - cash_amount,
        )
        closing.counted_cash_amount = max(
            Decimal("0"),
            closing.counted_cash_amount - cash_amount,
        )
        closing.cash_difference_amount = closing.counted_cash_amount - closing.expected_cash_amount
        closing.total_sales_amount = max(
            Decimal("0"),
            closing.total_sales_amount - received_amount,
        )
        closing.total_sales_count = max(0, closing.total_sales_count - 1)
        remaining_change = change_amount
        for payment in received_payments:
            payment_amount = payment.amount
            if payment.method == "dinheiro" and remaining_change > 0:
                change_applied = min(payment_amount, remaining_change)
                payment_amount -= change_applied
                remaining_change -= change_applied
            existing_payment = next(
                (item for item in closing.payments if item.method == payment.method),
                None,
            )
            if existing_payment is not None:
                existing_payment.amount = max(
                    Decimal("0"),
                    existing_payment.amount - payment_amount,
                )
        closing.movements.append(
            CashClosingMovement(
                movement_type="cancelamento_venda_administrativa",
                amount=received_amount,
                reason=f"Cancelamento da venda {sale.number}",
                created_at=sale.canceled_at or datetime.utcnow(),
            )
        )
        closing.treasury_notes = (
            f"Venda {sale.number} cancelada antes da conferencia do lote diario."
        )
        return
    closing.status = "divergent"
    closing.treasury_notes = (
        f"Venda {sale.number} cancelada apos conferencia do lote de caixa."
    )


@router.get("/sellers", response_model=list[SaleSellerRead])
def list_sellers(
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("sales:manual", "sales:create", "service_orders:sell")
    ),
) -> list[User]:
    return list(
        db.scalars(
            select(User)
            .where(User.active.is_(True))
            .order_by(User.name.asc(), User.id.asc())
        ).all()
    )


@router.post("", response_model=SaleRead, status_code=status.HTTP_201_CREATED)
def create_sale(
    sale_in: SaleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(
        require_any_permission("sales:manual", "sales:create", "service_orders:sell")
    ),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> Sale:
    offline_client_id = (sale_in.offline_client_id or "").strip() or None
    if offline_client_id:
        existing_sale = db.scalar(
            select(Sale).where(Sale.offline_client_id == offline_client_id)
        )
        if existing_sale is not None:
            return get_sale_or_404(db, existing_sale.id)

    client = db.get(Client, sale_in.client_id) if sale_in.client_id is not None else None
    if sale_in.client_id is not None and client is None:
        raise HTTPException(status_code=404, detail="Cliente não encontrado.")
    seller_user_id = sale_in.seller_user_id or current_user.id
    seller = db.get(User, seller_user_id)
    if seller is None or not seller.active:
        raise HTTPException(status_code=404, detail="Vendedor não encontrado ou inativo.")
    if sale_in.source == "os":
        if not user_has_configured_permission(db, current_user, "service_orders:sell"):
            raise HTTPException(
                status_code=403,
                detail="Usuario sem permissao para gerar venda da OS.",
            )
        if not (seller.seller_code or "").strip():
            raise HTTPException(
                status_code=400,
                detail="Venda da OS precisa de vendedor com codigo cadastrado.",
            )
    elif sale_in.source == "pdv":
        if not user_has_configured_permission(db, current_user, "sales:create"):
            raise HTTPException(
                status_code=403,
                detail="Usuario sem permissao para operar o PDV.",
            )
    else:
        if not user_has_configured_permission(db, current_user, "sales:manual"):
            raise HTTPException(
                status_code=403,
                detail="Usuario sem permissao para criar venda manual.",
            )
    if sale_in.cash_session_id is not None:
        cash_session = db.get(PdvCashSession, sale_in.cash_session_id)
        if cash_session is None:
            raise HTTPException(status_code=404, detail="Sessão de caixa não encontrada.")
        if cash_session.status != "open":
            raise HTTPException(status_code=409, detail="Sessão de caixa já encerrada.")
        if (
            sale_in.cash_register_number
            and cash_session.cash_register_number != sale_in.cash_register_number
        ):
            raise HTTPException(status_code=409, detail="Sessão de caixa pertence a outro caixa.")

    if (
        sale_in.source == "pdv"
        and sale_in.status == "finalizada"
        and offline_client_id is None
    ):
        price_changes: list[dict[str, object]] = []
        for item_in in sale_in.items:
            if item_in.product_id is None:
                continue
            product = db.get(Product, item_in.product_id)
            if product is None or not product.active:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "code": "PRODUCT_UNAVAILABLE",
                        "message": (
                            f"O produto {item_in.description} não está mais disponível. "
                            "Atualize o PDV antes de continuar."
                        ),
                        "product_id": item_in.product_id,
                    },
                )
            expected_price = effective_product_sale_price(product)
            if abs(expected_price - item_in.unit_price) > Decimal("0.0001"):
                price_changes.append(
                    {
                        "product_id": product.id,
                        "description": product.name,
                        "previous_price": str(item_in.unit_price),
                        "current_price": str(expected_price),
                    }
                )
        if price_changes:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "PRICE_CHANGED",
                    "message": (
                        "Um ou mais preços mudaram. O carrinho foi atualizado; "
                        "revise o total antes de cobrar."
                    ),
                    "changes": price_changes,
                },
            )

    sale = Sale(
        client_id=sale_in.client_id,
        seller_user_id=seller.id,
        source=sale_in.source,
        cash_register_number=sale_in.cash_register_number,
        cash_session_id=sale_in.cash_session_id,
        status=sale_in.status,
        discount_amount=sale_in.discount_amount,
        consumer_cpf=sale_in.consumer_cpf,
        offline_client_id=offline_client_id,
        notes=sale_in.notes,
    )

    subtotal = Decimal("0")
    stock_movements: list[dict[str, object]] = []
    for item_in in sale_in.items:
        product = db.get(Product, item_in.product_id) if item_in.product_id else None
        if item_in.product_id is not None and product is None:
            raise HTTPException(status_code=404, detail=f"Produto #{item_in.product_id} não encontrado.")

        unit = product.unit if product is not None else "un"
        barcode = item_in.barcode or (product.barcode if product is not None else None)
        line_total = money(
            (item_in.quantity * item_in.unit_price) - item_in.discount_amount
        )
        if line_total < 0:
            raise HTTPException(status_code=400, detail="Desconto do item maior que o total.")

        if sale_in.status == "finalizada" and product is not None and product.product_type != "servico":
            quantity_before = product.stock_quantity
            unit_cost, total_cost = apply_stock_out(product, item_in.quantity)
            stock_movements.append(
                {
                    "product": product,
                    "quantity_delta": -item_in.quantity,
                    "quantity_before": quantity_before,
                    "quantity_after": product.stock_quantity,
                    "unit": unit,
                    "unit_price": unit_cost,
                    "total_value": total_cost,
                }
            )

        sale.items.append(
            SaleItem(
                product_id=item_in.product_id,
                description=item_in.description,
                quantity=item_in.quantity,
                unit=unit,
                unit_price=item_in.unit_price,
                discount_amount=item_in.discount_amount,
                total_price=line_total,
                barcode=barcode,
            )
        )
        subtotal += line_total

    subtotal = money(subtotal)
    total = money(subtotal - sale_in.discount_amount)
    if total < 0:
        raise HTTPException(status_code=400, detail="Desconto maior que o total da venda.")
    if (
        sale_in.source in {"venda", "os"}
        and sale_in.discount_amount > 0
        and not user_has_configured_permission(
            db,
            current_user,
            "sales:discount:override",
        )
    ):
        settings = _sales_settings_for_company(_tenant_company_code(credentials))
        max_discount = money(
            subtotal * settings.max_discount_percent / Decimal("100")
        )
        if sale_in.discount_amount > max_discount + MONEY_TOLERANCE:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Desconto acima do limite permitido para vendas. "
                    f"Maximo permitido: {settings.max_discount_percent}%."
                ),
            )

    amount_paid = Decimal("0.00")
    financial_amount = Decimal("0.00")
    financial_methods: set[str] = set()
    installment_total = money(
        sum((money(item.amount) for item in sale_in.installments), Decimal("0"))
    )
    if sale_in.installments and len(sale_in.installments) > 12:
        raise HTTPException(status_code=400, detail="Venda permite no maximo 12 parcelas.")
    for payment_in in sale_in.payments:
        payment_amount = money(payment_in.amount)
        amount_paid += payment_amount
        if is_financial_payment(payment_in.method):
            financial_amount += payment_amount
            financial_methods.add(payment_in.method)
        payment_payload = payment_in.model_dump()
        payment_payload["amount"] = payment_amount
        sale.payments.append(SalePayment(**payment_payload))

    amount_paid = money(amount_paid)
    financial_amount = money(financial_amount)

    if sale_in.status == "finalizada" and amount_paid + MONEY_TOLERANCE < total:
        raise HTTPException(status_code=400, detail="Pagamento menor que o total da venda.")
    if sale_in.status == "finalizada" and abs(amount_paid - total) <= MONEY_TOLERANCE:
        amount_paid = total
    if sale_in.status == "finalizada" and financial_amount > 0:
        if client is None:
            raise HTTPException(
                status_code=400,
                detail="Venda boleto/crediario precisa ter cliente selecionado.",
            )
        if not client.active:
            raise HTTPException(
                status_code=400,
                detail="Cliente inativo não pode comprar no crediário.",
            )
        if "crediario" in financial_methods and not client.allow_credit:
            raise HTTPException(
                status_code=400,
                detail="Crediario desativado para este cliente.",
            )
        if "crediario" in financial_methods and client.credit_status != "liberado":
            raise HTTPException(
                status_code=400,
                detail="Cliente bloqueado para crediario.",
            )
        if sale_in.installments and abs(installment_total - financial_amount) > MONEY_TOLERANCE:
            raise HTTPException(
                status_code=400,
                detail="Total das parcelas precisa bater com o valor do boleto/crediario.",
            )
    if sale_in.installments and financial_amount <= 0:
        raise HTTPException(
            status_code=400,
            detail="Parcelas sao permitidas apenas para boleto ou crediario.",
        )

    sale.subtotal_amount = subtotal
    sale.total_amount = total
    sale.amount_paid = amount_paid
    sale.change_amount = money(amount_paid - total) if amount_paid > total else Decimal("0.00")

    db.add(sale)
    db.flush()
    sale.number = sale_number(sale.id)
    if financial_amount > 0 and sale_in.installments:
        for installment in sorted(sale_in.installments, key=lambda item: item.number):
            amount = money(installment.amount)
            receivable = Receivable(
                sale_id=sale.id,
                client_id=sale.client_id,
                description=(
                    f"{financial_description(financial_methods, sale.number)} "
                    f"parcela {installment.number}/{len(sale_in.installments)}"
                ),
                original_amount=amount,
                paid_amount=Decimal("0"),
                balance_amount=amount,
                status="open",
                due_date=installment.due_date,
                notes="Gerado automaticamente por venda parcelada.",
                entry_type="sale",
            )
            db.add(receivable)
            db.flush()
            receivable.number = receivable_number(receivable.id)
    elif financial_amount > 0:
        receivable = Receivable(
            sale_id=sale.id,
            client_id=sale.client_id,
            description=financial_description(financial_methods, sale.number),
            original_amount=financial_amount,
            paid_amount=Decimal("0"),
            balance_amount=financial_amount,
            status="open",
            notes="Gerado automaticamente por venda boleto/crediario.",
            entry_type="sale",
        )
        db.add(receivable)
        db.flush()
        receivable.number = receivable_number(receivable.id)
    create_administrative_cash_control(db, sale, current_user)
    sync_service_order_status_from_sale(
        db,
        sale,
        has_financial_receivable=financial_amount > 0,
        current_user=current_user,
    )
    for movement in stock_movements:
        product = movement["product"]
        apply_batch_out(
            db,
            product,
            -movement["quantity_delta"],
            source_type=sale.source,
            source_id=sale.id,
            source_number=sale.number,
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=current_user.id,
                movement_type="sale_out",
                source_type=sale.source,
                source_id=sale.id,
                source_number=sale.number,
                quantity_delta=movement["quantity_delta"],
                quantity_before=movement["quantity_before"],
                quantity_after=movement["quantity_after"],
                unit=movement["unit"],
                unit_price=movement["unit_price"],
                total_value=movement["total_value"],
                reason="Venda finalizada",
                notes=f"Baixa automatica da venda {sale.number}.",
            )
        )
    db.commit()
    return get_sale_or_404(db, sale.id)


@router.get("", response_model=list[SaleRead])
def list_sales(
    status_filter: str | None = Query(default=None, alias="status"),
    client_id: int | None = Query(default=None),
    date_from: date | None = Query(default=None),
    date_to: date | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=2000),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:view")),
) -> list[Sale]:
    query = (
        select(Sale)
        .options(
            selectinload(Sale.items),
            selectinload(Sale.payments),
            selectinload(Sale.seller),
            selectinload(Sale.fiscal_documents),
        )
        .order_by(Sale.sold_at.desc())
        .limit(limit)
    )
    if status_filter:
        query = query.where(Sale.status == status_filter)
    if client_id is not None:
        query = query.where(Sale.client_id == client_id)
    if date_from is not None:
        query = query.where(Sale.sold_at >= datetime.combine(date_from, time.min))
    if date_to is not None:
        query = query.where(Sale.sold_at <= datetime.combine(date_to, time.max))
    return list(db.scalars(query).all())


@router.get("/{sale_id}", response_model=SaleRead)
def get_sale(
    sale_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:view")),
) -> Sale:
    return get_sale_or_404(db, sale_id)


@router.post("/{sale_id}/cancel", response_model=SaleRead)
def cancel_sale(
    sale_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:cancel")),
) -> Sale:
    sale = get_sale_or_404(db, sale_id)
    if sale.status == "cancelada":
        return sale
    if sale.has_authorized_fiscal_document:
        raise HTTPException(
            status_code=409,
            detail=(
                "Venda possui nota fiscal autorizada. Cancele a NFC-e/NF-e "
                "na tela Notas fiscais antes de cancelar a venda."
            ),
        )
    if sale.status == "finalizada":
        for item in sale.items:
            if item.product_id is None:
                continue
            product = db.get(Product, item.product_id)
            if product is not None and product.product_type != "servico":
                quantity_before = product.stock_quantity
                unit_cost, total_cost = apply_stock_in(product, item.quantity, None)
                return_to_batch(
                    db,
                    product,
                    item.quantity,
                    source_type=sale.source,
                    source_id=sale.id,
                    source_number=sale.number,
                )
                db.add(
                    StockMovement(
                        product_id=product.id,
                        user_id=current_user.id,
                        movement_type="sale_cancel_return",
                        source_type=sale.source,
                        source_id=sale.id,
                        source_number=sale.number,
                        quantity_delta=item.quantity,
                        quantity_before=quantity_before,
                        quantity_after=product.stock_quantity,
                        unit=item.unit,
                        unit_price=unit_cost,
                        total_value=total_cost,
                        reason="Cancelamento de venda",
                        notes=f"Estorno automatico da venda {sale.number}.",
                    )
                )
    sale.status = "cancelada"
    sale.canceled_at = datetime.utcnow()
    cancel_sale_receivables(
        db,
        sale,
        current_user,
        f"Cancelado automaticamente pelo cancelamento da venda {sale.number}.",
    )
    mark_administrative_cash_control_canceled(db, sale)
    db.commit()
    return get_sale_or_404(db, sale_id)


@router.put("/{sale_id}/payments", response_model=SaleRead)
def update_sale_payments(
    sale_id: int,
    payload: SalePaymentsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("sales:manual", "sales:create")),
) -> Sale:
    sale = get_sale_or_404(db, sale_id)
    if sale.status == "cancelada":
        raise HTTPException(status_code=400, detail="Venda cancelada não pode ser alterada.")
    if sale.has_authorized_fiscal_document:
        raise HTTPException(
            status_code=409,
            detail=(
                "Venda possui nota fiscal autorizada. A forma de pagamento fiscal "
                "não deve ser alterada depois da autorização."
            ),
        )
    expected_amount = money(sale.amount_paid or sale.total_amount)
    new_amount = money(
        sum((money(payment.amount) for payment in payload.payments), Decimal("0"))
    )
    if abs(new_amount - expected_amount) > MONEY_TOLERANCE:
        raise HTTPException(
            status_code=400,
            detail="Total das formas de pagamento precisa bater com o valor recebido da venda.",
        )
    sale.payments.clear()
    db.flush()
    for payment_in in payload.payments:
        payment_payload = payment_in.model_dump()
        payment_payload["amount"] = money(payment_in.amount)
        sale.payments.append(SalePayment(**payment_payload))
    sync_sale_financial_receivable(db, sale, current_user)
    db.commit()
    return get_sale_or_404(db, sale_id)

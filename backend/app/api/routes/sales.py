from datetime import date, datetime, time
from decimal import Decimal, ROUND_HALF_UP

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_permission
from app.core.database import get_db
from app.models.cash_closing import CashClosing, CashClosingMovement, CashClosingPayment
from app.models.client import Client
from app.models.pdv_cash_session import PdvCashSession
from app.models.product import Product
from app.models.receivable import Receivable
from app.models.sale import Sale, SaleItem, SalePayment
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.sale import SaleCreate, SalePaymentsUpdate, SaleRead, SaleSellerRead
from app.services.product_batches import apply_batch_out, return_to_batch
from app.services.product_costs import apply_stock_in, apply_stock_out

router = APIRouter()

MONEY_QUANT = Decimal("0.01")
MONEY_TOLERANCE = Decimal("0.01")
FINANCIAL_PAYMENT_METHODS = {"boleto", "crediario"}


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def sale_number(sale_id: int) -> str:
    return f"V{sale_id}"


def receivable_number(receivable_id: int) -> str:
    return f"CR{receivable_id}"


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
    current_user: User = Depends(require_permission("sales:create")),
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
    current_user: User = Depends(require_permission("sales:create")),
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

    amount_paid = Decimal("0.00")
    financial_amount = Decimal("0.00")
    financial_methods: set[str] = set()
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

    sale.subtotal_amount = subtotal
    sale.total_amount = total
    sale.amount_paid = amount_paid
    sale.change_amount = money(amount_paid - total) if amount_paid > total else Decimal("0.00")

    db.add(sale)
    db.flush()
    sale.number = sale_number(sale.id)
    if financial_amount > 0:
        receivable = Receivable(
            sale_id=sale.id,
            client_id=sale.client_id,
            description=financial_description(financial_methods, sale.number),
            original_amount=financial_amount,
            paid_amount=Decimal("0"),
            balance_amount=financial_amount,
            status="open",
            notes="Gerado automaticamente por venda boleto/crediario.",
        )
        db.add(receivable)
        db.flush()
        receivable.number = receivable_number(receivable.id)
    create_administrative_cash_control(db, sale, current_user)
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
    current_user: User = Depends(require_permission("sales:create")),
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

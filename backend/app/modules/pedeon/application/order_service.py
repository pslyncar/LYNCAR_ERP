from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from math import ceil
import re
from urllib.parse import urlparse
from uuid import uuid4

import requests
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.modules.pedeon.application.order_schemas import (
    OrderDetailRead,
    OrderItemModifierRead,
    OrderItemRead,
    OrderPageRead,
    OrderSummaryRead,
)
from app.modules.pedeon.application.inventory_service import PedeOnInventoryService
from app.modules.pedeon.application.delivery_service import PedeOnDeliveryService
from app.modules.pedeon.application.operating_hours import store_is_accepting_orders
from app.modules.pedeon.application.public_catalog_service import (
    MONEY,
    PedeOnPublicCatalogService,
    ResolvedCartLine,
)
from app.modules.pedeon.application.public_schemas import (
    PublicOrderCreate,
    PublicOrderRead,
    PublicPaymentRead,
)
from app.modules.pedeon.domain.lifecycle import (
    FulfillmentType,
    OrderStatus,
    PaymentMethod,
    PaymentStatus,
    ensure_order_transition,
    ensure_payment_transition,
)
from app.modules.pedeon.domain.channels import OrderSource, normalize_source_channel
from app.modules.pedeon.domain.fulfillment import (
    resolve_fulfillment_mode,
    resolve_print_policy,
)
from app.modules.pedeon.infrastructure.database.models import (
    PedeOnFulfillmentStation,
    PedeOnFulfillmentTask,
    PedeOnOrder,
    PedeOnOrderEvent,
    PedeOnOrderItem,
    PedeOnOrderItemModifier,
    PedeOnOutboxEvent,
    PedeOnPaymentConfiguration,
    PedeOnPaymentTransaction,
    PedeOnPrintJob,
    PedeOnProductPublication,
    PedeOnStore,
)
from app.services.tenancy import session_for_company


class PedeOnPublicOrderService:
    @classmethod
    def create(cls, slug: str, payload: PublicOrderCreate) -> PublicOrderRead:
        registry = PedeOnPublicCatalogService._registry(slug)
        with session_for_company(registry.company_code) as db:
            existing = db.scalar(
                select(PedeOnOrder).where(
                    PedeOnOrder.store_id == registry.tenant_store_id,
                    PedeOnOrder.idempotency_key == payload.idempotency_key,
                )
            )
            if existing is not None:
                return cls._public_read(db, existing)

            store = PedeOnPublicCatalogService._active_store(
                db, registry.tenant_store_id, slug
            )
            cls._validate_store(store, payload)
            config = cls._payment_configuration(db, store.id, payload.payment_method)
            if payload.payment_method == PaymentMethod.PAY_AT_PICKUP:
                configuration = config.public_configuration or {}
                methods_key = (
                    "delivery_methods"
                    if payload.fulfillment_type == FulfillmentType.DELIVERY
                    else "accepted_methods"
                )
                configured_methods = configuration.get(methods_key)
                # Older stores stored the local payment methods only in
                # accepted_methods. Keep that configuration valid for delivery
                # until the owner saves the new per-fulfillment settings.
                if (
                    payload.fulfillment_type == FulfillmentType.DELIVERY
                    and configured_methods is None
                ):
                    configured_methods = configuration.get("accepted_methods", [])
                accepted_methods = set(
                    configured_methods
                    if configured_methods is not None
                    else ["cash", "pix", "credit_card", "debit_card"]
                )
                if payload.local_payment_method not in accepted_methods:
                    raise ValueError("Selecione uma forma de pagamento no local disponível.")
            snapshots = PedeOnPublicCatalogService.resolve_cart(
                db, store, payload.items
            )
            subtotal = sum((line.total for line in snapshots), Decimal("0"))
            subtotal = subtotal.quantize(MONEY, rounding=ROUND_HALF_UP)
            if subtotal < Decimal(store.minimum_order_amount).quantize(MONEY):
                raise ValueError("O valor mínimo do pedido ainda não foi atingido.")
            delivery = None
            if payload.fulfillment_type == FulfillmentType.DELIVERY:
                delivery = PedeOnDeliveryService(db).quote(
                    store, payload.delivery_address, subtotal
                )
            delivery_fee = delivery.fee if delivery else Decimal("0.00")
            if (
                payload.local_payment_method == "cash"
                and payload.cash_change_for is not None
                and payload.cash_change_for < subtotal + delivery_fee
            ):
                raise ValueError("O troco deve ser maior ou igual ao total do pedido.")

            pay_after_order = payload.payment_method in {
                PaymentMethod.CREDIT_CARD_ON_DELIVERY,
                PaymentMethod.DEBIT_CARD_ON_DELIVERY,
                PaymentMethod.PAY_AT_PICKUP,
            }
            payment_status = (
                PaymentStatus.AWAITING_MANUAL_CONFIRMATION
                if payload.payment_method == PaymentMethod.MANUAL_PIX
                else PaymentStatus.PENDING
            )
            order = PedeOnOrder(
                idempotency_key=payload.idempotency_key,
                store_id=store.id,
                source_channel=OrderSource.PEDEON,
                source_metadata={
                    "entrypoint": "public_catalog",
                    **(
                        {"local_payment_method": payload.local_payment_method}
                        if payload.local_payment_method is not None
                        else {}
                    ),
                    **(
                        {"cash_change_for": str(payload.cash_change_for)}
                        if payload.cash_change_for is not None
                        else {}
                    ),
                },
                status=(
                    OrderStatus.AWAITING_ACCEPTANCE
                    if pay_after_order
                    else OrderStatus.AWAITING_PAYMENT
                ),
                payment_status=payment_status,
                fulfillment_type=payload.fulfillment_type,
                customer_name=payload.customer_name.strip(),
                customer_phone=payload.customer_phone.strip(),
                customer_email=(payload.customer_email or "").strip() or None,
                customer_document=(payload.customer_document or "").strip() or None,
                delivery_address=(
                    {
                        **payload.delivery_address.model_dump(),
                        "zone_id": delivery.zone_id if delivery else None,
                        "zone_name": delivery.zone_name if delivery else None,
                        "estimated_minutes_min": (
                            delivery.estimated_minutes_min if delivery else None
                        ),
                        "estimated_minutes_max": (
                            delivery.estimated_minutes_max if delivery else None
                        ),
                    }
                    if payload.delivery_address is not None
                    else None
                ),
                subtotal_amount=subtotal,
                delivery_fee_amount=delivery_fee,
                total_amount=(subtotal + delivery_fee).quantize(MONEY),
                customer_notes=(payload.customer_notes or "").strip() or None,
            )
            db.add(order)
            try:
                db.flush()
            except IntegrityError:
                db.rollback()
                existing = db.scalar(
                    select(PedeOnOrder).where(
                        PedeOnOrder.store_id == store.id,
                        PedeOnOrder.idempotency_key == payload.idempotency_key,
                    )
                )
                if existing is None:
                    raise
                return cls._public_read(db, existing)
            order.display_number = f"PED-{order.id:06d}"

            reservation_demands: dict[int, dict[int, Decimal]] = {}
            for sort_order, line in enumerate(snapshots):
                order_item = PedeOnOrderItem(
                        order_id=order.id,
                        product_id=line.product.id,
                        publication_id=line.publication.id,
                        product_code=line.product.internal_code,
                        barcode=line.product.barcode,
                        description=line.publication.display_name or line.product.name,
                        quantity=line.request.quantity,
                        unit=line.product.unit,
                        unit_price=line.base_unit_price,
                        modifiers_amount=line.modifiers_unit_amount,
                        total_amount=line.total,
                        customer_notes=(line.request.customer_notes or "").strip() or None,
                        fiscal_snapshot={
                            "ncm": line.product.ncm,
                            "cest": line.product.cest,
                            "cfop_sale": line.product.cfop_sale,
                            "origin": line.product.origin,
                            "cst": line.product.cst,
                            "csosn": line.product.csosn,
                        },
                        sort_order=sort_order,
                    )
                db.add(order_item)
                db.flush()
                if line.product.product_type != "servico":
                    reservation_demands.setdefault(order_item.id, {})[
                        line.product.id
                    ] = Decimal(line.request.quantity)
                for sequence, modifier in enumerate(line.modifiers):
                    db.add(
                        PedeOnOrderItemModifier(
                            order_item_id=order_item.id,
                            group_id=modifier.group.id,
                            option_id=modifier.option.id,
                            group_name=modifier.group.name,
                            option_name=modifier.option.name,
                            quantity=modifier.quantity,
                            unit_price=modifier.unit_price,
                            total_amount=modifier.total,
                            sequence=sequence,
                        )
                    )
                    if modifier.option.product_id is not None:
                        product_demands = reservation_demands.setdefault(
                            order_item.id, {}
                        )
                        product_demands[modifier.option.product_id] = (
                            product_demands.get(
                                modifier.option.product_id, Decimal("0")
                            )
                            + Decimal(modifier.quantity)
                            * Decimal(line.request.quantity)
                        )
            PedeOnInventoryService(db).reserve(order, reservation_demands)
            # Pagamento no local não aguarda confirmação online. A reserva
            # deixa de ser temporária para que o pedido possa aguardar preparo
            # sem ser cancelado pelo vencimento do checkout.
            if payload.payment_method == PaymentMethod.PAY_AT_PICKUP:
                PedeOnInventoryService(db).commit(order.id)
            provider = "manual"
            if payload.payment_method == PaymentMethod.INFINITEPAY_PIX:
                provider = "infinitepay"
            elif payload.payment_method == PaymentMethod.PAY_AT_PICKUP:
                provider = "pickup_local"
            elif payload.payment_method in {
                PaymentMethod.CREDIT_CARD_ON_DELIVERY,
                PaymentMethod.DEBIT_CARD_ON_DELIVERY,
            }:
                provider = "delivery_terminal"

            transaction = PedeOnPaymentTransaction(
                order_id=order.id,
                idempotency_key=f"{payload.idempotency_key}:payment",
                method=payload.payment_method,
                provider=provider,
                status=payment_status,
                amount=order.total_amount,
                metadata_payload={
                    **(
                        {"local_payment_method": payload.local_payment_method}
                        if payload.local_payment_method is not None
                        else {}
                    ),
                    **(
                        {"cash_change_for": str(payload.cash_change_for)}
                        if payload.cash_change_for is not None
                        else {}
                    ),
                },
            )
            db.add(transaction)
            try:
                # A cobrança precisa existir antes de o pedido ser confirmado.
                # Caso a InfinitePay falhe, o rollback evita pedidos órfãos em
                # "aguardando pagamento" sem QR Code ou link de pagamento.
                if payload.payment_method == PaymentMethod.INFINITEPAY_PIX:
                    cls._create_infinitepay_checkout(
                        db, slug, order, transaction, config, snapshots
                    )
                cls._events(db, order)
                db.commit()
            except Exception:
                db.rollback()
                raise
            db.refresh(order)
            return cls._public_read(db, order)

    @classmethod
    def track(cls, slug: str, tracking_token: str) -> PublicOrderRead:
        registry = PedeOnPublicCatalogService._registry(slug)
        with session_for_company(registry.company_code) as db:
            order = db.scalar(
                select(PedeOnOrder).where(
                    PedeOnOrder.store_id == registry.tenant_store_id,
                    PedeOnOrder.tracking_token == tracking_token,
                )
            )
            if order is None:
                raise LookupError("Pedido não encontrado.")
            return cls._public_read(db, order)

    @classmethod
    def process_infinitepay_webhook(cls, slug: str, payload: dict) -> dict:
        registry = PedeOnPublicCatalogService._registry(slug)
        order_nsu = str(payload.get("order_nsu") or "").strip()
        transaction_nsu = str(payload.get("transaction_nsu") or "").strip()
        invoice_slug = str(payload.get("invoice_slug") or payload.get("slug") or "").strip()
        if not order_nsu or not transaction_nsu or not invoice_slug:
            raise ValueError("Notificação de pagamento incompleta.")
        with session_for_company(registry.company_code) as db:
            order = db.scalar(
                select(PedeOnOrder).where(
                    PedeOnOrder.store_id == registry.tenant_store_id,
                    PedeOnOrder.public_id == order_nsu,
                ).with_for_update()
            )
            if order is None:
                raise LookupError("Pedido não encontrado.")
            transaction = db.scalar(
                select(PedeOnPaymentTransaction).where(
                    PedeOnPaymentTransaction.order_id == order.id,
                    PedeOnPaymentTransaction.method == PaymentMethod.INFINITEPAY_PIX,
                )
            )
            if transaction is None:
                raise LookupError("Pagamento InfinitePay não encontrado.")
            if transaction.status == PaymentStatus.CONFIRMED:
                return {"success": True, "message": None}
            config = cls._payment_configuration(
                db, order.store_id, PaymentMethod.INFINITEPAY_PIX
            )
            settings = get_settings()
            check = requests.post(
                "https://api.checkout.infinitepay.io/payment_check",
                json={
                    "handle": (config.public_configuration or {}).get("handle", ""),
                    "order_nsu": order.public_id,
                    "transaction_nsu": transaction_nsu,
                    "slug": invoice_slug,
                },
                timeout=settings.pedeon_payment_timeout_seconds,
            )
            check.raise_for_status()
            result = check.json()
            expected_cents = int((Decimal(transaction.amount) * 100).quantize(Decimal("1")))
            if not result.get("success") or not result.get("paid"):
                raise ValueError("Pagamento ainda não confirmado pela InfinitePay.")
            if int(result.get("amount") or 0) != expected_cents:
                raise ValueError("Valor confirmado pela InfinitePay diverge do pedido.")

            now = datetime.now(timezone.utc)
            transaction.status = PaymentStatus.CONFIRMED
            transaction.provider_transaction_id = transaction_nsu
            transaction.provider_invoice_slug = invoice_slug
            transaction.receipt_url = str(payload.get("receipt_url") or "") or None
            transaction.confirmed_at = now
            transaction.updated_at = now
            transaction.metadata_payload = {
                "capture_method": result.get("capture_method"),
                "installments": result.get("installments"),
                "paid_amount": result.get("paid_amount"),
            }
            order.payment_status = PaymentStatus.CONFIRMED
            PedeOnInventoryService(db).commit(order.id)
            ensure_order_transition(
                OrderStatus(order.status),
                OrderStatus.AWAITING_ACCEPTANCE,
                fulfillment_type=FulfillmentType(order.fulfillment_type),
            )
            order.status = OrderStatus.AWAITING_ACCEPTANCE
            order.version += 1
            store = db.get(PedeOnStore, order.store_id)
            if (
                config.auto_accept_after_confirmation
                and store is not None
                and store.acceptance_mode in {"automatic", "mixed"}
            ):
                PedeOnOrderService(db)._accept_and_start_preparation(
                    order,
                    actor_type="provider",
                    actor_id="infinitepay",
                )
            target = OrderStatus(order.status)
            event_key = str(uuid4())
            db.add(
                PedeOnOrderEvent(
                    event_key=event_key,
                    order_id=order.id,
                    event_type="pedeon.payment.confirmed",
                    from_status=OrderStatus.AWAITING_PAYMENT,
                    to_status=target,
                    order_version=order.version,
                    actor_type="provider",
                    actor_id="infinitepay",
                    payload={
                        "transaction_nsu": transaction_nsu,
                        "source_channel": order.source_channel,
                    },
                )
            )
            db.add(
                PedeOnOutboxEvent(
                    event_key=f"{event_key}:outbox",
                    aggregate_type="order",
                    aggregate_id=order.public_id,
                    event_type="pedeon.payment.confirmed",
                    payload={
                        "status": target,
                        "payment_method": transaction.method,
                        "source_channel": order.source_channel,
                    },
                )
            )
            db.commit()
            return {"success": True, "message": None}

    @staticmethod
    def _validate_store(store: PedeOnStore, payload: PublicOrderCreate) -> None:
        if not store_is_accepting_orders(store):
            raise ValueError("A loja está fechada para novos pedidos.")
        if payload.fulfillment_type not in (store.fulfillment_options or []):
            raise ValueError("Esta forma de recebimento não está disponível.")
        if payload.fulfillment_type == FulfillmentType.DELIVERY and payload.delivery_address is None:
            raise ValueError("Informe o endereço para entrega.")
        if payload.fulfillment_type == FulfillmentType.PICKUP and payload.delivery_address is not None:
            raise ValueError("Pedido para retirada não deve conter endereço de entrega.")
        if (
            payload.payment_method
            in {
                PaymentMethod.CREDIT_CARD_ON_DELIVERY,
                PaymentMethod.DEBIT_CARD_ON_DELIVERY,
            }
            and payload.fulfillment_type != FulfillmentType.DELIVERY
        ):
            raise ValueError("Pagamento na maquininha está disponível somente para entrega.")
        if payload.payment_method == PaymentMethod.PAY_AT_PICKUP:
            if payload.fulfillment_type not in {
                FulfillmentType.PICKUP,
                FulfillmentType.DELIVERY,
            }:
                raise ValueError("Forma de recebimento inválida para pagamento local.")
            if payload.local_payment_method is None:
                raise ValueError("Selecione a forma de pagamento no local.")
        elif payload.local_payment_method is not None or payload.cash_change_for is not None:
            raise ValueError("A forma de pagamento no local não se aplica a este pagamento.")
        if payload.local_payment_method != "cash" and payload.cash_change_for is not None:
            raise ValueError("O troco só pode ser informado para pagamento em dinheiro.")

    @staticmethod
    def _payment_configuration(
        db: Session, store_id: int, method: str
    ) -> PedeOnPaymentConfiguration:
        config = db.scalar(
            select(PedeOnPaymentConfiguration).where(
                PedeOnPaymentConfiguration.store_id == store_id,
                PedeOnPaymentConfiguration.method == method,
                PedeOnPaymentConfiguration.enabled.is_(True),
            )
        )
        if config is None:
            raise ValueError("Esta forma de pagamento não está disponível.")
        return config

    @staticmethod
    def _events(db: Session, order: PedeOnOrder) -> None:
        event_key = str(uuid4())
        db.add(
            PedeOnOrderEvent(
                event_key=event_key,
                order_id=order.id,
                event_type="pedeon.order.created",
                to_status=order.status,
                order_version=order.version,
                actor_type="customer",
                actor_id=order.public_id,
                payload={
                    "display_number": order.display_number,
                    "source_channel": order.source_channel,
                    "external_order_id": order.external_order_id,
                },
            )
        )
        db.add(
            PedeOnOutboxEvent(
                event_key=f"{event_key}:outbox",
                aggregate_type="order",
                aggregate_id=order.public_id,
                event_type="pedeon.order.created",
                payload={
                    "order_id": order.public_id,
                    "display_number": order.display_number,
                    "source_channel": order.source_channel,
                    "external_order_id": order.external_order_id,
                },
            )
        )

    @classmethod
    def _create_infinitepay_checkout(
        cls,
        db: Session,
        slug: str,
        order: PedeOnOrder,
        transaction: PedeOnPaymentTransaction,
        config: PedeOnPaymentConfiguration,
        snapshots: list[ResolvedCartLine],
    ) -> None:
        settings = get_settings()
        body = {
            "handle": (config.public_configuration or {}).get("handle", ""),
            "order_nsu": order.public_id,
            "items": [
                cls._infinitepay_item(line) for line in snapshots
            ]
            + (
                [
                    {
                        "quantity": 1,
                        "price": int(
                            (Decimal(order.delivery_fee_amount) * 100).quantize(
                                Decimal("1")
                            )
                        ),
                        "description": "Taxa de entrega",
                    }
                ]
                if Decimal(order.delivery_fee_amount) > 0
                else []
            ),
        }
        customer = cls._infinitepay_customer(order)
        if customer is not None:
            body["customer"] = customer

        # A InfinitePay precisa conseguir chamar essas URLs. Em desenvolvimento
        # local elas apontam para localhost e são recusadas pelo provedor; nesse
        # caso o checkout continua válido, só não há retorno automático local.
        public_base = settings.pedeon_public_base_url.rstrip("/")
        if cls._is_public_https_url(public_base):
            body["redirect_url"] = f"{public_base}/{slug}?pedido={order.tracking_token}"

        api_base = settings.pedeon_api_public_url.rstrip("/")
        if cls._is_public_https_url(api_base):
            body["webhook_url"] = (
                f"{api_base}/pedeon/public/{slug}/payments/infinitepay/webhook"
            )
        try:
            response = requests.post(
                "https://api.checkout.infinitepay.io/links",
                json=body,
                timeout=settings.pedeon_payment_timeout_seconds,
            )
            response.raise_for_status()
            response_body = response.json()
            if not isinstance(response_body, dict):
                raise ValueError("A InfinitePay retornou uma resposta inválida.")
            # A documentação pública da InfinitePay mostra `url`, enquanto a
            # referência OpenAPI mais recente também usa `checkout_url`.
            # Aceitamos ambos para não descartar uma cobrança criada com êxito.
            checkout_url = str(
                response_body.get("url") or response_body.get("checkout_url") or ""
            ).strip()
            if not checkout_url:
                raise ValueError("A InfinitePay não retornou o link de pagamento.")
            transaction.checkout_url = checkout_url
            transaction.updated_at = datetime.now(timezone.utc)
        except requests.RequestException as exc:
            provider_message = cls._infinitepay_error_message(exc)
            raise ValueError(
                "Não foi possível criar a cobrança na InfinitePay. "
                f"{provider_message}"
            ) from exc
        except (TypeError, ValueError) as exc:
            raise ValueError(
                "A InfinitePay não retornou uma cobrança válida. "
                "Confira a configuração do Pix InfinitePay e tente novamente."
            ) from exc

    @staticmethod
    def _infinitepay_customer(order: PedeOnOrder) -> dict | None:
        phone_digits = re.sub(r"\D", "", order.customer_phone or "")
        if len(phone_digits) in {10, 11}:
            phone_number = f"+55{phone_digits}"
        elif phone_digits.startswith("55") and len(phone_digits) in {12, 13}:
            phone_number = f"+{phone_digits}"
        else:
            # Cliente é opcional no Checkout. Não enviamos um telefone em
            # formato inválido, pois a API da InfinitePay recusa o pedido todo.
            return None

        customer = {
            "name": (order.customer_name or "").strip(),
            "phone_number": phone_number,
        }
        email = (order.customer_email or "").strip()
        if email:
            customer["email"] = email
        return customer

    @staticmethod
    def _is_public_https_url(value: str) -> bool:
        parsed = urlparse(value)
        host = (parsed.hostname or "").lower()
        return (
            parsed.scheme == "https"
            and bool(host)
            and host not in {"localhost", "127.0.0.1", "::1"}
        )

    @staticmethod
    def _infinitepay_error_message(exc: requests.RequestException) -> str:
        response = getattr(exc, "response", None)
        if response is None:
            return "Verifique a conexão e tente novamente."
        try:
            payload = response.json()
        except ValueError:
            payload = None
        if isinstance(payload, dict):
            detail = payload.get("message") or payload.get("error") or payload.get("detail")
            if isinstance(detail, str) and detail.strip():
                return detail.strip()
        return "Confira a configuração do Pix InfinitePay e tente novamente."

    @staticmethod
    def _infinitepay_item(
        line: ResolvedCartLine,
    ) -> dict:
        description = line.publication.display_name or line.product.name
        if line.modifiers:
            description += " - " + ", ".join(
                modifier.option.name for modifier in line.modifiers
            )
        quantity = line.request.quantity
        line_total = line.total
        if quantity == quantity.to_integral_value():
            return {
                "quantity": int(quantity),
                "price": int((line_total / quantity * 100).quantize(Decimal("1"))),
                "description": description,
            }
        return {
            "quantity": 1,
            "price": int((line_total * 100).quantize(Decimal("1"))),
            "description": f"{description} ({quantity} {line.product.unit})",
        }

    @staticmethod
    def _public_read(db: Session, order: PedeOnOrder) -> PublicOrderRead:
        transaction = db.scalar(
            select(PedeOnPaymentTransaction)
            .where(PedeOnPaymentTransaction.order_id == order.id)
            .order_by(PedeOnPaymentTransaction.id.desc())
        )
        if transaction is None:
            raise LookupError("Pagamento do pedido não encontrado.")
        config = db.scalar(
            select(PedeOnPaymentConfiguration).where(
                PedeOnPaymentConfiguration.store_id == order.store_id,
                PedeOnPaymentConfiguration.method == transaction.method,
            )
        )
        public = config.public_configuration if config else {}
        return PublicOrderRead(
            order_id=order.public_id,
            tracking_token=order.tracking_token,
            display_number=order.display_number or f"PED-{order.id:06d}",
            status=order.status,
            payment_status=order.payment_status,
            fulfillment_type=order.fulfillment_type,
            customer_name=order.customer_name,
            subtotal=order.subtotal_amount,
            delivery_fee=order.delivery_fee_amount,
            total=order.total_amount,
            delivery_zone_name=(order.delivery_address or {}).get("zone_name"),
            estimated_minutes_min=(order.delivery_address or {}).get(
                "estimated_minutes_min"
            ),
            estimated_minutes_max=(order.delivery_address or {}).get(
                "estimated_minutes_max"
            ),
            created_at=order.created_at,
            payment=PublicPaymentRead(
                method=transaction.method,
                status=transaction.status,
                display_name=config.display_name if config and config.display_name else transaction.method,
                checkout_url=transaction.checkout_url,
                pix_key=public.get("pix_key") if transaction.method == "manual_pix" else None,
                pix_key_type=public.get("key_type") if transaction.method == "manual_pix" else None,
                recipient_name=public.get("recipient_name") if transaction.method == "manual_pix" else None,
                instructions=public.get("instructions") if transaction.method == "manual_pix" else None,
            ),
        )


class PedeOnOrderService:
    def __init__(self, db: Session):
        self.db = db

    def list(
        self,
        status_filter: str | None,
        source_filter: str | None,
        page: int,
        page_size: int,
    ) -> OrderPageRead:
        query = select(PedeOnOrder)
        if status_filter:
            query = query.where(PedeOnOrder.status == status_filter)
        if source_filter:
            query = query.where(
                PedeOnOrder.source_channel == normalize_source_channel(source_filter)
            )
        total = self.db.scalar(select(func.count()).select_from(query.subquery())) or 0
        orders = self.db.scalars(
            query.order_by(PedeOnOrder.created_at.desc(), PedeOnOrder.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return OrderPageRead(
            items=[self._summary(order) for order in orders],
            page=page,
            page_size=page_size,
            total=total,
            total_pages=max(1, ceil(total / page_size)),
        )

    def detail(self, order_id: int) -> OrderDetailRead:
        order = self.db.get(PedeOnOrder, order_id)
        if order is None:
            raise LookupError("Pedido não encontrado.")
        items = self.db.scalars(
            select(PedeOnOrderItem)
            .where(PedeOnOrderItem.order_id == order.id)
            .order_by(PedeOnOrderItem.sort_order, PedeOnOrderItem.id)
        ).all()
        item_ids = [item.id for item in items]
        modifiers_by_item: dict[int, list[PedeOnOrderItemModifier]] = {
            item_id: [] for item_id in item_ids
        }
        if item_ids:
            modifiers = self.db.scalars(
                select(PedeOnOrderItemModifier)
                .where(PedeOnOrderItemModifier.order_item_id.in_(item_ids))
                .order_by(
                    PedeOnOrderItemModifier.order_item_id,
                    PedeOnOrderItemModifier.sequence,
                    PedeOnOrderItemModifier.id,
                )
            ).all()
            for modifier in modifiers:
                modifiers_by_item[modifier.order_item_id].append(modifier)
        stations_by_item: dict[int, PedeOnFulfillmentStation] = {}
        if item_ids:
            station_rows = self.db.execute(
                select(PedeOnFulfillmentTask.order_item_id, PedeOnFulfillmentStation)
                .join(
                    PedeOnFulfillmentStation,
                    PedeOnFulfillmentStation.id == PedeOnFulfillmentTask.station_id,
                )
                .where(PedeOnFulfillmentTask.order_item_id.in_(item_ids))
            ).all()
            for item_id, station in station_rows:
                if item_id is not None:
                    stations_by_item[item_id] = station
        transaction = self.db.scalar(
            select(PedeOnPaymentTransaction)
            .where(PedeOnPaymentTransaction.order_id == order.id)
            .order_by(PedeOnPaymentTransaction.id.desc())
        )
        return OrderDetailRead(
            **self._summary(order).model_dump(),
            customer_email=order.customer_email,
            customer_document=order.customer_document,
            delivery_address=order.delivery_address,
            customer_notes=order.customer_notes,
            subtotal=order.subtotal_amount,
            discount=order.discount_amount,
            delivery_fee=order.delivery_fee_amount,
            payment_method=transaction.method if transaction else None,
            local_payment_method=(order.source_metadata or {}).get("local_payment_method"),
            cash_change_for=(order.source_metadata or {}).get("cash_change_for"),
            source_metadata=order.source_metadata or {},
            accepted_at=order.accepted_at,
            preparation_started_at=order.preparation_started_at,
            ready_at=order.ready_at,
            out_for_delivery_at=order.out_for_delivery_at,
            completed_at=order.completed_at,
            items=[
                OrderItemRead(
                    product_id=item.product_id,
                    description=item.description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    total=item.total_amount,
                    customer_notes=item.customer_notes,
                    station_code=(
                        stations_by_item[item.id].code
                        if item.id in stations_by_item
                        else None
                    ),
                    station_name=(
                        stations_by_item[item.id].name
                        if item.id in stations_by_item
                        else None
                    ),
                    modifiers=[
                        OrderItemModifierRead(
                            group_name=modifier.group_name,
                            option_name=modifier.option_name,
                            quantity=modifier.quantity,
                            unit_price=modifier.unit_price,
                            total=modifier.total_amount,
                        )
                        for modifier in modifiers_by_item[item.id]
                    ],
                )
                for item in items
            ],
        )

    def transition(
        self,
        order_id: int,
        target_value: str,
        actor_id: int,
        *,
        actor_type: str = "user",
    ) -> OrderDetailRead:
        order = self.db.scalar(
            select(PedeOnOrder)
            .where(PedeOnOrder.id == order_id)
            .with_for_update()
        )
        if order is None:
            raise LookupError("Pedido não encontrado.")
        current = OrderStatus(order.status)
        target = OrderStatus(target_value)
        if target == OrderStatus.ACCEPTED and current in {
            OrderStatus.ACCEPTED,
            OrderStatus.IN_PREPARATION,
            OrderStatus.READY,
            OrderStatus.OUT_FOR_DELIVERY,
            OrderStatus.COMPLETED,
        }:
            return self.detail(order.id)
        ensure_order_transition(
            current, target, fulfillment_type=FulfillmentType(order.fulfillment_type)
        )
        if current != target:
            if target == OrderStatus.ACCEPTED:
                self._accept_and_start_preparation(
                    order,
                    actor_type=actor_type,
                    actor_id=str(actor_id),
                )
            else:
                self._apply_transition(
                    order,
                    target,
                    actor_type=actor_type,
                    actor_id=str(actor_id),
                )
            self.db.commit()
        return self.detail(order.id)

    def _accept_and_start_preparation(
        self,
        order: PedeOnOrder,
        *,
        actor_type: str,
        actor_id: str,
    ) -> None:
        """Aceita e despacha para a produção uma única vez.

        A criação das tarefas e da impressão ocorre na mesma transação das
        mudanças de estado. A chave do trabalho de impressão torna o fluxo
        seguro contra repetição da mesma operação.
        """

        current = OrderStatus(order.status)
        if current == OrderStatus.AWAITING_ACCEPTANCE:
            PedeOnInventoryService(self.db).commit(order.id)
            self._apply_transition(
                order,
                OrderStatus.ACCEPTED,
                actor_type=actor_type,
                actor_id=actor_id,
            )
        elif current != OrderStatus.ACCEPTED:
            ensure_order_transition(
                current,
                OrderStatus.ACCEPTED,
                fulfillment_type=FulfillmentType(order.fulfillment_type),
            )

        if OrderStatus(order.status) == OrderStatus.ACCEPTED:
            _, plans = self._operational_plan(order)
            self._apply_transition(
                order,
                OrderStatus.IN_PREPARATION if plans else OrderStatus.READY,
                actor_type="system",
                actor_id="pedeon-fulfillment",
            )

    def _apply_transition(
        self,
        order: PedeOnOrder,
        target: OrderStatus,
        *,
        actor_type: str,
        actor_id: str,
    ) -> None:
        current = OrderStatus(order.status)
        ensure_order_transition(
            current,
            target,
            fulfillment_type=FulfillmentType(order.fulfillment_type),
        )
        if current == target:
            return

        if target == OrderStatus.IN_PREPARATION:
            self._provision_production(order)

        inventory = PedeOnInventoryService(self.db)
        if target == OrderStatus.COMPLETED:
            inventory.consume(order)
        elif target == OrderStatus.CANCELLED:
            inventory.release(order.id, "order_cancelled")

        now = datetime.now(timezone.utc)
        order.status = target
        order.version += 1
        if target == OrderStatus.ACCEPTED:
            order.accepted_at = now
        elif target == OrderStatus.IN_PREPARATION:
            order.preparation_started_at = now
        elif target == OrderStatus.READY:
            order.ready_at = now
            self._finish_production_tasks(order.id, now)
        elif target == OrderStatus.OUT_FOR_DELIVERY:
            order.out_for_delivery_at = now
        elif target == OrderStatus.COMPLETED:
            order.completed_at = now
            from app.modules.pedeon.application.sale_bridge import PedeOnSaleBridge

            PedeOnSaleBridge(self.db).ensure_sale(
                order, actor_type=actor_type, actor_id=actor_id
            )
        elif target == OrderStatus.CANCELLED:
            order.cancelled_at = now
            self._cancel_production(order.id, now)

        payload = {
            "status": target.value,
            "source_channel": order.source_channel,
            "external_order_id": order.external_order_id,
        }
        event_key = str(uuid4())
        self.db.add(
            PedeOnOrderEvent(
                event_key=event_key,
                order_id=order.id,
                event_type="pedeon.order.status.changed",
                from_status=current,
                to_status=target,
                order_version=order.version,
                actor_type=actor_type,
                actor_id=actor_id,
                payload=payload,
            )
        )
        self.db.add(
            PedeOnOutboxEvent(
                event_key=f"{event_key}:outbox",
                aggregate_type="order",
                aggregate_id=order.public_id,
                event_type="pedeon.order.status.changed",
                payload=payload,
            )
        )
        # Em mesa/comanda, o caixa pode receber enquanto a cozinha ainda está
        # preparando. Quando a cozinha termina um pedido já pago, a conta não
        # precisa voltar ao caixa: conclui, baixa a reserva e preserva o
        # histórico operacional.
        if (
            target == OrderStatus.READY
            and order.payment_status == PaymentStatus.CONFIRMED
            and FulfillmentType(order.fulfillment_type) == FulfillmentType.DINE_IN
        ):
            self._apply_transition(
                order,
                OrderStatus.COMPLETED,
                actor_type="system",
                actor_id="pedeon-paid-dine-in",
            )

    def _operational_plan(
        self, order: PedeOnOrder
    ) -> tuple[
        list[PedeOnOrderItem],
        dict[tuple[str, str | None], list[PedeOnOrderItem]],
    ]:
        items = self.db.scalars(
            select(PedeOnOrderItem)
            .where(PedeOnOrderItem.order_id == order.id)
            .order_by(PedeOnOrderItem.sort_order, PedeOnOrderItem.id)
        ).all()
        store = self.db.get(PedeOnStore, order.store_id)
        if store is None:
            raise LookupError("Configuração da loja PedeOn não encontrada.")
        publication_ids = [item.publication_id for item in items if item.publication_id]
        publications = {
            publication.id: publication
            for publication in self.db.scalars(
                select(PedeOnProductPublication).where(
                    PedeOnProductPublication.id.in_(publication_ids)
                )
            ).all()
        } if publication_ids else {}
        plans: dict[tuple[str, str | None], list[PedeOnOrderItem]] = {}
        for item in items:
            publication = publications.get(item.publication_id)
            mode = resolve_fulfillment_mode(
                store.default_fulfillment_mode,
                publication.fulfillment_mode if publication else "inherit",
            )
            if mode == "none":
                continue
            station_code = None
            if publication is not None:
                station_code = (publication.availability_rules or {}).get(
                    "production_station_code"
                )
            plans.setdefault((mode, station_code), []).append(item)
        return list(items), plans

    def _provision_production(self, order: PedeOnOrder) -> None:
        _, plans = self._operational_plan(order)
        store = self.db.get(PedeOnStore, order.store_id)
        if store is None:
            raise LookupError("Configuração da loja PedeOn não encontrada.")
        station_definitions = {
            "preparation": ("kitchen", "Cozinha / Produção", "preparation"),
            "picking": ("picking", "Separação", "picking"),
        }
        now = datetime.now(timezone.utc)
        for (mode, custom_station_code), items in plans.items():
            default_code, default_name, station_type = station_definitions[mode]
            code = custom_station_code or default_code
            name = (
                custom_station_code.replace("-", " ").replace("_", " ").title()
                if custom_station_code
                else default_name
            )
            station = self.db.scalar(
                select(PedeOnFulfillmentStation).where(
                    PedeOnFulfillmentStation.store_id == order.store_id,
                    PedeOnFulfillmentStation.code == code,
                )
            )
            if station is None:
                station = PedeOnFulfillmentStation(
                    store_id=order.store_id,
                    code=code,
                    name=name,
                    station_type=station_type,
                    sort_order=0,
                    active=True,
                )
                self.db.add(station)
                self.db.flush()
            existing_item_ids = set(
                self.db.scalars(
                    select(PedeOnFulfillmentTask.order_item_id).where(
                        PedeOnFulfillmentTask.order_id == order.id,
                        PedeOnFulfillmentTask.station_id == station.id,
                    )
                ).all()
            )
            for item in items:
                if item.id not in existing_item_ids:
                    self.db.add(
                        PedeOnFulfillmentTask(
                            order_id=order.id,
                            order_item_id=item.id,
                            station_id=station.id,
                            status="in_preparation",
                            version=1,
                            started_at=now,
                        )
                    )
            self._provision_print_job(order, store, station, items)

    def _provision_print_job(
        self,
        order: PedeOnOrder,
        store: PedeOnStore,
        station: PedeOnFulfillmentStation,
        items: list[PedeOnOrderItem],
    ) -> None:
        publication_ids = [item.publication_id for item in items if item.publication_id]
        publications = {
            publication.id: publication
            for publication in self.db.scalars(
                select(PedeOnProductPublication).where(
                    PedeOnProductPublication.id.in_(publication_ids)
                )
            ).all()
        } if publication_ids else {}
        printable_items = []
        for item in items:
            policy = resolve_print_policy(
                store.production_print_policy,
                publications.get(item.publication_id).print_policy
                if item.publication_id in publications
                else "inherit",
            )
            if policy == "automatic":
                printable_items.append(item)
        if not printable_items:
            return

        job_key = f"order:{order.public_id}:station:{station.id}:production:v1"
        existing_job = self.db.scalar(
            select(PedeOnPrintJob).where(PedeOnPrintJob.job_key == job_key)
        )
        if existing_job is None:
            modifiers = self.db.scalars(
                select(PedeOnOrderItemModifier)
                .join(
                    PedeOnOrderItem,
                    PedeOnOrderItem.id == PedeOnOrderItemModifier.order_item_id,
                )
                .where(PedeOnOrderItem.order_id == order.id)
                .order_by(
                    PedeOnOrderItemModifier.order_item_id,
                    PedeOnOrderItemModifier.sequence,
                )
            ).all()
            modifiers_by_item: dict[int, list[PedeOnOrderItemModifier]] = {}
            for modifier in modifiers:
                modifiers_by_item.setdefault(modifier.order_item_id, []).append(modifier)
            self.db.add(
                PedeOnPrintJob(
                    job_key=job_key,
                    order_id=order.id,
                    station_id=station.id,
                    document_type="production_ticket",
                    status="pending",
                    payload={
                        "station_id": station.id,
                        "station_code": station.code,
                        "station_name": station.name,
                        "display_number": order.display_number,
                        "source_channel": order.source_channel,
                        "table_label": order.table_label,
                        "command_label": order.command_label,
                        "external_order_id": order.external_order_id,
                        "customer_name": order.customer_name,
                        "fulfillment_type": order.fulfillment_type,
                        "customer_notes": order.customer_notes,
                        "items": [
                            {
                                "description": item.description,
                                "quantity": str(item.quantity),
                                "unit": item.unit,
                                "notes": item.customer_notes,
                                "modifiers": [
                                    {
                                        "group": modifier.group_name,
                                        "option": modifier.option_name,
                                        "quantity": str(modifier.quantity),
                                    }
                                    for modifier in modifiers_by_item.get(item.id, [])
                                ],
                            }
                            for item in printable_items
                        ],
                    },
                )
            )

    def _finish_production_tasks(self, order_id: int, now: datetime) -> None:
        tasks = self.db.scalars(
            select(PedeOnFulfillmentTask).where(
                PedeOnFulfillmentTask.order_id == order_id,
                PedeOnFulfillmentTask.status != "completed",
            )
        ).all()
        for task in tasks:
            task.status = "completed"
            task.completed_at = now
            task.version += 1

    def _cancel_production(self, order_id: int, now: datetime) -> None:
        tasks = self.db.scalars(
            select(PedeOnFulfillmentTask).where(
                PedeOnFulfillmentTask.order_id == order_id,
                PedeOnFulfillmentTask.status != "completed",
            )
        ).all()
        for task in tasks:
            task.status = "cancelled"
            task.completed_at = now
            task.version += 1
        jobs = self.db.scalars(
            select(PedeOnPrintJob).where(
                PedeOnPrintJob.order_id == order_id,
                PedeOnPrintJob.status == "pending",
            )
        ).all()
        for job in jobs:
            job.status = "cancelled"

    def confirm_payment(self, order_id: int, actor_id: int) -> OrderDetailRead:
        order = self.db.scalar(
            select(PedeOnOrder)
            .where(PedeOnOrder.id == order_id)
            .with_for_update()
        )
        if order is None:
            raise LookupError("Pedido não encontrado.")
        transaction = self.db.scalar(
            select(PedeOnPaymentTransaction)
            .where(PedeOnPaymentTransaction.order_id == order.id)
            .order_by(PedeOnPaymentTransaction.id.desc())
        )
        supported = {
            PaymentMethod.MANUAL_PIX,
            PaymentMethod.CREDIT_CARD_ON_DELIVERY,
            PaymentMethod.DEBIT_CARD_ON_DELIVERY,
        }
        if transaction is None or transaction.method not in supported:
            raise ValueError("Este pagamento não permite confirmação manual.")
        ensure_payment_transition(
            PaymentStatus(transaction.status),
            PaymentStatus.CONFIRMED,
            payment_method=PaymentMethod(transaction.method),
        )
        if transaction.status != PaymentStatus.CONFIRMED:
            now = datetime.now(timezone.utc)
            previous_order_status = OrderStatus(order.status)
            transaction.status = PaymentStatus.CONFIRMED
            transaction.confirmed_by_user_id = actor_id
            transaction.confirmed_at = now
            transaction.updated_at = now
            order.payment_status = PaymentStatus.CONFIRMED
            PedeOnInventoryService(self.db).commit(order.id)
            if order.status == OrderStatus.AWAITING_PAYMENT:
                order.status = OrderStatus.AWAITING_ACCEPTANCE
                order.version += 1
            event_key = str(uuid4())
            self.db.add(
                PedeOnOrderEvent(
                    event_key=event_key,
                    order_id=order.id,
                    event_type="pedeon.payment.confirmed",
                    from_status=previous_order_status,
                    to_status=order.status,
                    order_version=order.version,
                    actor_type="user",
                    actor_id=str(actor_id),
                    payload={
                        "payment_method": transaction.method,
                        "source_channel": order.source_channel,
                    },
                )
            )
            self.db.add(
                PedeOnOutboxEvent(
                    event_key=f"{event_key}:outbox",
                    aggregate_type="order",
                    aggregate_id=order.public_id,
                    event_type="pedeon.payment.confirmed",
                    payload={
                        "status": order.status,
                        "source_channel": order.source_channel,
                    },
                )
            )
            self.db.commit()
        return self.detail(order.id)

    @staticmethod
    def _summary(order: PedeOnOrder) -> OrderSummaryRead:
        return OrderSummaryRead(
            id=order.id,
            public_id=order.public_id,
            display_number=order.display_number or f"PED-{order.id:06d}",
            source_channel=order.source_channel,
            external_order_id=order.external_order_id,
            status=order.status,
            payment_status=order.payment_status,
            fulfillment_type=order.fulfillment_type,
            customer_name=order.customer_name,
            customer_phone=order.customer_phone,
            total=order.total_amount,
            created_at=order.created_at,
        )

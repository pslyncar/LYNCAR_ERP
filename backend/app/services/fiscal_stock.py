from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.fiscal import FiscalDocument, FiscalDocumentItem
from app.models.product import Product
from app.models.stock_entry import StockEntry, StockEntryItem


def refresh_product_fiscal_balance(db: Session, product_id: int) -> None:
    product = db.get(Product, product_id)
    if product is None:
        return

    received_row = db.execute(
        select(
            func.coalesce(func.sum(StockEntryItem.received_quantity), 0),
            func.count(func.distinct(StockEntry.id)),
        )
        .join(StockEntry, StockEntry.id == StockEntryItem.stock_entry_id)
        .where(
            StockEntry.status == "confirmed",
            StockEntryItem.product_id == product_id,
            StockEntryItem.check_status == "accepted",
            StockEntryItem.received_quantity > 0,
        )
    ).one()
    received = Decimal(str(received_row[0] or 0))
    entry_count = int(received_row[1] or 0)

    issued = Decimal(
        str(
            db.scalar(
                select(func.coalesce(func.sum(FiscalDocumentItem.quantity), 0))
                .join(
                    FiscalDocument,
                    FiscalDocument.id == FiscalDocumentItem.fiscal_document_id,
                )
                .where(
                    FiscalDocument.status == "authorized",
                    FiscalDocumentItem.fiscal_product_id == product_id,
                    FiscalDocumentItem.included.is_(True),
                )
            )
            or 0
        )
    )
    available = received - issued
    if available < 0:
        available = Decimal("0")

    product.fiscal_received_quantity = received
    product.fiscal_issued_quantity = issued
    product.fiscal_available_quantity = available
    product.fiscal_entry_count = entry_count


def refresh_many_product_fiscal_balances(db: Session, product_ids: set[int]) -> None:
    for product_id in product_ids:
        refresh_product_fiscal_balance(db, product_id)

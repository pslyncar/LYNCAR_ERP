from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, model_validator


STOCK_WITHDRAWAL_REASONS = {
    "loss_damage",
    "expired",
    "internal_consumption",
    "employee_meal",
    "production_use",
    "sample_gift",
    "theft",
    "inventory_adjustment",
    "other",
}


class StockWithdrawalCreate(BaseModel):
    quantity: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    reason_code: str = Field(min_length=3, max_length=40)
    notes: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def validate_reason(self) -> "StockWithdrawalCreate":
        if self.reason_code not in STOCK_WITHDRAWAL_REASONS:
            raise ValueError("Motivo de baixa de estoque invalido.")
        notes = (self.notes or "").strip()
        if self.reason_code == "other" and len(notes) < 5:
            raise ValueError("Informe uma observacao para o motivo Outros.")
        self.notes = notes or None
        return self


class StockAdjustmentCreate(BaseModel):
    """Recontagem ou correção de saldo, sempre registrada no histórico."""

    counted_quantity: Decimal = Field(max_digits=12, decimal_places=3)
    reason_code: str = Field(min_length=3, max_length=40)
    notes: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def validate_reason(self) -> "StockAdjustmentCreate":
        if self.reason_code not in {"inventory_count", "data_correction", "other"}:
            raise ValueError("Motivo de ajuste de estoque invalido.")
        notes = (self.notes or "").strip()
        if len(notes) < 5:
            raise ValueError("Informe uma observacao de ao menos 5 caracteres.")
        self.notes = notes
        return self


class StockMovementRead(BaseModel):
    id: int
    product_id: int
    user_id: int | None
    movement_type: str
    source_type: str | None
    source_id: int | None
    source_number: str | None
    quantity_delta: Decimal
    quantity_before: Decimal
    quantity_after: Decimal
    unit: str
    unit_price: Decimal | None
    total_value: Decimal | None
    reason: str | None
    notes: str | None
    supplier_name: str | None = None
    supplier_document: str | None = None
    invoice_key: str | None = None
    invoice_number: str | None = None
    invoice_series: str | None = None
    batch_number: str | None = None
    expiration_date: date | None = None
    received_quantity: Decimal | None = None
    check_status: str | None = None
    check_notes: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class StockWithdrawalRead(StockMovementRead):
    product_name: str
    user_name: str | None = None

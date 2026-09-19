from datetime import datetime
from decimal import Decimal
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.modules.pedeon.domain.lifecycle import TerminalCapability


class StoreSettingsUpdate(BaseModel):
    public_slug: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", min_length=3, max_length=80)
    display_name: str = Field(min_length=2, max_length=180)
    description: str | None = Field(default=None, max_length=1200)
    logo_url: str | None = Field(default=None, max_length=500)
    cover_url: str | None = Field(default=None, max_length=500)
    accent_color: str = Field(default="#075E6F", pattern=r"^#[0-9A-Fa-f]{6}$")
    dark_mode: bool = False
    active: bool = False
    accepting_orders: bool = False
    acceptance_mode: Literal["manual", "automatic", "mixed"] = "manual"
    experience_mode: Literal["food_service", "retail"] = "food_service"
    business_segment: Literal[
        "restaurant", "burger", "bakery", "market", "fashion", "accessories",
        "automotive", "services", "other"
    ] = "other"
    default_fulfillment_mode: Literal["preparation", "picking", "none"] = "preparation"
    production_print_policy: Literal["disabled", "manual", "automatic"] = "manual"
    inventory_policy: Literal["warn_allow", "strict_block", "untracked"] = "warn_allow"
    fulfillment_options: list[Literal["pickup", "delivery"]] = Field(min_length=1)
    minimum_order_amount: Decimal = Field(default=Decimal("0"), ge=0)

    @model_validator(mode="after")
    def validate_experience_fulfillment(self):
        incompatible = (
            self.experience_mode == "food_service"
            and self.default_fulfillment_mode == "picking"
        ) or (
            self.experience_mode == "retail"
            and self.default_fulfillment_mode == "preparation"
        )
        if incompatible:
            raise ValueError("O fluxo padrão não corresponde ao tipo da loja.")
        return self


class StoreSettingsRead(StoreSettingsUpdate):
    model_config = ConfigDict(from_attributes=True)

    id: int


class ManualPixUpdate(BaseModel):
    enabled: bool = False
    pickup_enabled: bool = True
    delivery_enabled: bool = True
    key_type: Literal["cpf", "cnpj", "email", "phone", "random"] = "random"
    pix_key: str = Field(default="", max_length=180)
    recipient_name: str = Field(default="", max_length=180)
    instructions: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_enabled_configuration(self):
        if self.enabled and (not self.pix_key.strip() or not self.recipient_name.strip()):
            raise ValueError("Informe a chave Pix e o nome do recebedor.")
        return self


class InfinitePayUpdate(BaseModel):
    enabled: bool = False
    pickup_enabled: bool = True
    delivery_enabled: bool = True
    handle: str = Field(default="", max_length=120)
    auto_accept_after_confirmation: bool = True

    @model_validator(mode="after")
    def validate_enabled_configuration(self):
        if self.enabled and not self.handle.strip():
            raise ValueError("Informe o identificador da InfinitePay.")
        return self


class DeliveryCardUpdate(BaseModel):
    cash_enabled: bool = False
    pix_enabled: bool = False
    credit_enabled: bool = False
    debit_enabled: bool = False


class PickupPaymentUpdate(BaseModel):
    enabled: bool = False
    accepted_methods: list[Literal["cash", "pix", "credit_card", "debit_card"]] = Field(
        default_factory=lambda: ["cash", "pix", "credit_card", "debit_card"],
        min_length=1,
    )


class BusinessHoursDay(BaseModel):
    enabled: bool = False
    open_time: str = Field(default="08:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    close_time: str = Field(default="18:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


class DeliveryOperationUpdate(BaseModel):
    pricing_mode: Literal["fixed", "zones"] = "zones"
    fixed_fee_amount: Decimal = Field(default=Decimal("0"), ge=0)
    fixed_minimum_order_amount: Decimal = Field(default=Decimal("0"), ge=0)
    fixed_free_delivery_threshold: Decimal | None = Field(default=None, ge=0)
    preparation_minutes_min: int = Field(default=20, ge=1, le=1440)
    preparation_minutes_max: int = Field(default=35, ge=1, le=1440)
    opening_mode: Literal["manual", "schedule"] = "manual"
    weekly_hours: dict[str, BusinessHoursDay] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_delivery_operation(self):
        if self.preparation_minutes_min > self.preparation_minutes_max:
            raise ValueError("O tempo mínimo de preparo não pode superar o máximo.")
        if (
            self.fixed_free_delivery_threshold is not None
            and self.fixed_free_delivery_threshold < self.fixed_minimum_order_amount
        ):
            raise ValueError("A entrega grátis não pode começar abaixo do pedido mínimo.")
        allowed_days = {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}
        if not set(self.weekly_hours).issubset(allowed_days):
            raise ValueError("A agenda contém um dia inválido.")
        for day in self.weekly_hours.values():
            if day.enabled and day.open_time == day.close_time:
                raise ValueError("Abertura e fechamento não podem ter o mesmo horário.")
        return self


class PaymentSettingsRead(BaseModel):
    manual_pix: ManualPixUpdate
    infinitepay: InfinitePayUpdate
    delivery_card: DeliveryCardUpdate
    pickup_payment: PickupPaymentUpdate


class TerminalPermissionUpdate(BaseModel):
    enabled: bool = False
    capabilities: list[TerminalCapability] = Field(default_factory=list)
    notification_mode: Literal["badge", "sound", "silent"] = "badge"
    priority: int = Field(default=100, ge=0, le=9999)
    device_role: Literal["kitchen", "cashier", "dining_room"] = "cashier"

    @model_validator(mode="after")
    def ensure_view_capability(self):
        if self.enabled and TerminalCapability.VIEW not in self.capabilities:
            self.capabilities.insert(0, TerminalCapability.VIEW)
        return self


class TerminalPermissionRead(TerminalPermissionUpdate):
    terminal_id: int
    cash_register_number: str
    device_label: str | None = None
    app_version: str | None = None
    terminal_active: bool
    last_seen_at: datetime | None = None
    status: str = "offline"


class DeliveryZoneInput(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    match_type: Literal["postal_code_prefix", "neighborhood", "radius"]
    postal_code_prefix: str | None = Field(default=None, min_length=3, max_length=8)
    neighborhood: str | None = Field(default=None, min_length=2, max_length=120)
    city: str | None = Field(default=None, min_length=2, max_length=120)
    state: str | None = Field(default=None, min_length=2, max_length=2)
    center_latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    center_longitude: Decimal | None = Field(default=None, ge=-180, le=180)
    radius_km: Decimal | None = Field(default=None, gt=0, le=500)
    fee_amount: Decimal = Field(default=Decimal("0"), ge=0)
    minimum_order_amount: Decimal = Field(default=Decimal("0"), ge=0)
    free_delivery_threshold: Decimal | None = Field(default=None, ge=0)
    estimated_minutes_min: int | None = Field(default=None, ge=1, le=1440)
    estimated_minutes_max: int | None = Field(default=None, ge=1, le=1440)
    sort_order: int = Field(default=0, ge=0, le=9999)
    active: bool = True

    @model_validator(mode="after")
    def validate_match_and_estimate(self):
        if self.match_type == "postal_code_prefix":
            digits = "".join(char for char in (self.postal_code_prefix or "") if char.isdigit())
            if len(digits) < 3:
                raise ValueError("Informe ao menos 3 dígitos do CEP.")
            self.postal_code_prefix = digits
            self.neighborhood = None
        elif self.match_type == "neighborhood" and not (self.neighborhood or "").strip():
            raise ValueError("Informe o bairro atendido.")
        elif self.match_type == "radius" and (
            self.center_latitude is None
            or self.center_longitude is None
            or self.radius_km is None
        ):
            raise ValueError("Localize o ponto central e informe o raio da área.")
        if (
            self.estimated_minutes_min is not None
            and self.estimated_minutes_max is not None
            and self.estimated_minutes_min > self.estimated_minutes_max
        ):
            raise ValueError("O prazo mínimo não pode superar o prazo máximo.")
        if (
            self.free_delivery_threshold is not None
            and self.free_delivery_threshold < self.minimum_order_amount
        ):
            raise ValueError("A entrega grátis não pode começar abaixo do pedido mínimo.")
        if self.state is not None:
            self.state = self.state.strip().upper()
        return self


class DeliveryZoneRead(DeliveryZoneInput):
    model_config = ConfigDict(from_attributes=True)

    id: int


class FulfillmentStationInput(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    code: str = Field(min_length=2, max_length=60)
    station_type: Literal["preparation", "picking", "expedition"] = "preparation"
    sort_order: int = Field(default=0, ge=0, le=9999)
    active: bool = True

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        cleaned = value.strip().lower().replace(" ", "-")
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,59}", cleaned):
            raise ValueError("Use apenas letras, números, hífen e sublinhado no código.")
        return cleaned


class FulfillmentStationRead(FulfillmentStationInput):
    model_config = ConfigDict(from_attributes=True)

    id: int


class PedeOnSettingsRead(BaseModel):
    store: StoreSettingsRead
    payments: PaymentSettingsRead
    terminals: list[TerminalPermissionRead]
    delivery_zones: list[DeliveryZoneRead] = Field(default_factory=list)
    fulfillment_stations: list[FulfillmentStationRead] = Field(default_factory=list)
    delivery_operation: DeliveryOperationUpdate = Field(default_factory=DeliveryOperationUpdate)


class CategoryCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    active: bool = True
    channel: Literal["online", "salon", "shared"] = "shared"


class CategoryUpdate(CategoryCreate):
    sort_order: int = Field(default=0, ge=0, le=9999)


class CategoryRead(CategoryUpdate):
    id: int
    slug: str


class CategoryReorder(BaseModel):
    category_ids: list[int] = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def validate_unique_ids(self):
        if len(self.category_ids) != len(set(self.category_ids)):
            raise ValueError("A ordem contém categorias duplicadas.")
        return self


class ModifierOptionInput(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    price_delta: Decimal = Field(default=Decimal("0"), ge=0)
    product_id: int | None = None
    sort_order: int = Field(default=0, ge=0, le=9999)
    active: bool = True
    minimum_quantity: int = Field(default=1, ge=1, le=50)
    maximum_quantity: int | None = Field(default=1, ge=1, le=50)

    @model_validator(mode="after")
    def validate_quantity_limits(self):
        if self.maximum_quantity is not None and self.minimum_quantity > self.maximum_quantity:
            raise ValueError("A quantidade máxima deve ser maior ou igual à mínima.")
        return self


class ModifierOptionRead(ModifierOptionInput):
    id: int
    code: str


class ModifierGroupInput(BaseModel):
    name: str = Field(min_length=2, max_length=140)
    description: str | None = Field(default=None, max_length=500)
    minimum_selections: int = Field(default=0, ge=0, le=50)
    maximum_selections: int | None = Field(default=1, ge=1, le=50)
    sort_order: int = Field(default=0, ge=0, le=9999)
    active: bool = True
    channel: Literal["online", "salon", "shared"] = "shared"
    kind: Literal["observation", "complement", "product"] = "complement"
    options: list[ModifierOptionInput] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def validate_selection_limits(self):
        if (
            self.maximum_selections is not None
            and self.minimum_selections > self.maximum_selections
        ):
            raise ValueError("O máximo de escolhas deve ser maior ou igual ao mínimo.")
        if self.minimum_selections > len([item for item in self.options if item.active]):
            raise ValueError("O grupo não possui opções ativas suficientes para o mínimo.")
        if self.kind == "observation" and any(item.product_id is not None for item in self.options):
            raise ValueError("Perguntas de observação não podem usar produtos do estoque.")
        return self


class ModifierGroupRead(ModifierGroupInput):
    id: int
    code: str
    options: list[ModifierOptionRead]


class PublicationUpdate(BaseModel):
    category_id: int | None = None
    online_category_id: int | None = None
    salon_category_id: int | None = None
    display_name: str | None = Field(default=None, max_length=220)
    description: str | None = Field(default=None, max_length=1200)
    image_url: str | None = None
    online_price: Decimal | None = Field(default=None, ge=0)
    published: bool = False
    available: bool = True
    published_channels: list[str] = Field(default_factory=list, max_length=4)
    available_channels: list[str] = Field(default_factory=list, max_length=4)
    use_product_offer: bool = True
    fulfillment_mode: Literal["inherit", "preparation", "picking", "none"] = "inherit"
    print_policy: Literal["inherit", "disabled", "manual", "automatic"] = "inherit"
    enabled_channels: list[
        Literal["pedeon_online", "onsite_qr", "onsite_waiter", "pdv_counter"]
    ] = Field(default_factory=lambda: ["pedeon_online"], max_length=4)
    production_station_code: str | None = Field(default=None, max_length=60)
    sort_order: int = Field(default=0, ge=0, le=9999)
    modifier_group_ids: list[int] = Field(default_factory=list, max_length=50)
    online_modifier_group_ids: list[int] = Field(default_factory=list, max_length=50)
    salon_modifier_group_ids: list[int] = Field(default_factory=list, max_length=50)

    @field_validator("enabled_channels")
    @classmethod
    def unique_channels(cls, value: list[str]) -> list[str]:
        return list(dict.fromkeys(value))

    @field_validator("production_station_code")
    @classmethod
    def normalize_station(cls, value: str | None) -> str | None:
        cleaned = (value or "").strip().lower().replace(" ", "-")
        if not cleaned:
            return None
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,59}", cleaned):
            raise ValueError("Use apenas letras, números, hífen e sublinhado na estação.")
        return cleaned


class CatalogProductRead(PublicationUpdate):
    product_id: int
    publication_id: int | None = None
    product_name: str
    internal_code: str | None = None
    barcode: str | None = None
    product_image_url: str | None = None
    product_description: str | None = None
    sale_price: Decimal
    offer_price: Decimal | None = None
    stock_quantity: Decimal
    unit: str
    product_active: bool


class CatalogPageRead(BaseModel):
    items: list[CatalogProductRead]
    categories: list[CategoryRead]
    modifier_groups: list[ModifierGroupRead] = Field(default_factory=list)
    page: int
    page_size: int
    total: int
    total_pages: int

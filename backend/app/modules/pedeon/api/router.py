import secrets
import time
from urllib.parse import urlencode, urlparse

import requests
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, Response, UploadFile, status
from fastapi.responses import RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import bearer_scheme, require_permission
from app.core.config import get_settings
from app.core.database import get_db
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token, hash_password, verify_password
from app.models.user import User
from app.models.pdv_cash_session import PdvCashSession
from app.models.pdv_operator import PdvOperator
from app.models.pdv_terminal import PdvTerminal
from app.modules.pedeon.application.schemas import (
    DeliveryCardUpdate,
    DeliveryOperationUpdate,
    DeliveryZoneInput,
    DeliveryZoneRead,
    FulfillmentStationInput,
    FulfillmentStationRead,
    CatalogPageRead,
    CatalogProductRead,
    CategoryCreate,
    CategoryRead,
    CategoryReorder,
    CategoryUpdate,
    InfinitePayUpdate,
    ManualPixUpdate,
    PickupPaymentUpdate,
    ModifierGroupInput,
    ModifierGroupRead,
    PedeOnSettingsRead,
    StoreSettingsUpdate,
    TerminalPermissionUpdate,
    PublicationUpdate,
)
from app.modules.pedeon.application.catalog_service import PedeOnCatalogService
from app.modules.pedeon.application.settings_service import PedeOnSettingsService
from app.modules.pedeon.application.public_catalog_service import PedeOnPublicCatalogService
from app.services.uploads import save_public_image
from app.modules.pedeon.application.public_url import public_store_path, public_store_url
from app.modules.pedeon.application.public_schemas import (
    CartQuoteRead,
    CartQuoteRequest,
    EdgeCatalogRead,
    PublicCatalogPageRead,
    PublicOrderCreate,
    PublicOrderRead,
    PublicCustomerAuthInput,
    PublicCustomerAuthRead,
    PublicCustomerProfileUpdate,
)
from app.modules.pedeon.application.customer_auth import (
    clear_customer_cookie,
    normalize_email,
    public_customer,
    read_customer,
    set_customer_cookie,
    token_for,
)
from app.modules.pedeon.application.customer_identity import (
    attach_local_customer,
    global_customer_for,
    update_global_profile,
)
from app.modules.pedeon.infrastructure.database.models import PedeOnCustomer, PedeOnStore
from app.services.master_pedeon_social import get_configs
from app.services.tenancy import session_for_company
from app.modules.pedeon.application.order_schemas import (
    OrderDetailRead,
    OrderPageRead,
    OrderStatusUpdate,
    TerminalFeedRead,
    TerminalPrintJobRead,
    TerminalPrintJobResult,
)
from app.modules.pedeon.application.order_service import (
    PedeOnOrderService,
    PedeOnPublicOrderService,
)
from app.modules.pedeon.application.terminal_service import PedeOnTerminalService
from app.modules.pedeon.application.edge_schemas import (
    EdgeHeartbeatRequest,
    EdgeNodeRead,
    EdgeRegisterRequest,
    EdgeTerminalAuthorizationRead,
    EdgeTerminalAuthorizeRequest,
)
from app.modules.pedeon.application.edge_service import PedeOnEdgeService
from app.modules.pedeon.application.checkout_service import PedeOnCheckoutService
from app.modules.pedeon.application.staff_order_service import PedeOnStaffOrderService
from app.modules.pedeon.application.staff_schemas import (
    EdgeCashSessionOpen,
    EdgeOrderCheckout,
    EdgeStaffOrderCreate,
)

router = APIRouter()

_SOCIAL_STATE_TTL_SECONDS = 600
_SOCIAL_CODE_TTL_SECONDS = 120
_SOCIAL_STATES: dict[str, tuple[str, float, str]] = {}
_SOCIAL_CODES: dict[str, tuple[str, int, str, float]] = {}


def require_pedeon_activation_owner(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> User:
    """Only the first tenant user can bootstrap a PedeOn Edge installation.

    This is deliberately based on the immutable first user record, not on the
    mutable ``admin`` role. Other ERP administrators may manage operations but
    cannot silently bind a new PedeOn installation.
    """
    first_user = db.scalar(select(User).order_by(User.id.asc()))
    if first_user is None or first_user.id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Somente o primeiro usuario da empresa pode ativar o PedeOn.",
        )
    return current_user


@router.get("/terminals")
def list_pedeon_terminals(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> list[dict]:
    """Expose the PedeOn terminal contract without coupling clients to /pdv."""
    terminals = list(
        db.scalars(
            select(PdvTerminal).order_by(
                PdvTerminal.active.desc(),
                PdvTerminal.cash_register_number.asc(),
                PdvTerminal.id.asc(),
            )
        ).all()
    )
    return [
        {
            "id": terminal.id,
            "cash_register_number": terminal.cash_register_number,
            "terminal_key": terminal.terminal_key,
            "device_label": terminal.device_label,
            "active": terminal.active,
            "activation_status": terminal.activation_status,
        }
        for terminal in terminals
    ]


@router.post("/edge/cash-sessions/open")
def open_edge_cash_session(
    payload: EdgeCashSessionOpen,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("sales:create")),
) -> dict:
    try:
        store, terminal = PedeOnEdgeService(db).authorize_checkout(payload)
        del store
        operator = None
        if payload.operator_type == "erp_owner":
            # Somente o primeiro usuário da empresa pode entrar como dono no
            # PedeOn. Os demais usuários do ERP não são operadores PedeOn;
            # devem ser cadastrados em PedeOn > Operadores para acessar como
            # ``pedeon_operator``.
            first_user = db.scalar(select(User).order_by(User.id.asc()))
            if first_user is None or first_user.id != current_user.id:
                raise PermissionError(
                    "Somente o primeiro usuário da empresa pode abrir o caixa como dono."
                )
            # Eventos locais são persistidos para serem reenviados pelo Edge.
            # Um evento criado durante a inicialização pode conter o operador
            # provisório; nesse caso, o único valor aceito é o primeiro
            # usuário autenticado, nunca um usuário arbitrário do ERP.
            if payload.operator_id == 0 and payload.operator_name == "Usuário PedeOn":
                payload.operator_id = current_user.id
                payload.operator_name = current_user.name
            if current_user.id != payload.operator_id:
                raise PermissionError("O caixa deve ser aberto pelo usuário atualmente logado.")
            if current_user.name != payload.operator_name:
                raise PermissionError("Usuário autenticado não corresponde ao operador do caixa.")
        else:
            operator = db.get(PdvOperator, payload.operator_id)
            if (
                operator is None
                or operator.role != "pedeon_operator"
                or not operator.active
                or not operator.can_open_cash
                or operator.name != payload.operator_name
            ):
                raise PermissionError("Operador PedeOn não autorizado para abrir caixa.")
        existing = db.scalar(
            select(PdvCashSession).where(
                PdvCashSession.status == "open",
                PdvCashSession.cash_register_number == payload.cash_register_number,
                PdvCashSession.terminal_key == terminal.terminal_key,
            )
        )
        if existing is None:
            existing = PdvCashSession(
                cash_register_number=payload.cash_register_number,
                terminal_key=terminal.terminal_key,
                operator_id=operator.id if operator is not None else None,
                operator_name=operator.name if operator is not None else current_user.name,
                opening_amount=payload.opening_amount,
                status="open",
                last_heartbeat_at=datetime.now(timezone.utc),
                created_by_user_id=current_user.id,
            )
            db.add(existing)
            db.commit()
            db.refresh(existing)
        return {"id": existing.id, "local_key": payload.local_key, "status": existing.status}
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/edge/orders", response_model=OrderDetailRead, status_code=201)
def create_edge_staff_order(
    payload: EdgeStaffOrderCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> OrderDetailRead:
    try:
        store, terminal = PedeOnEdgeService(db).authorize_staff_order(payload)
        return PedeOnStaffOrderService(db).create(store, payload, terminal.id)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/edge/orders/{order_id}/checkout")
def checkout_edge_order(
    order_id: str,
    payload: EdgeOrderCheckout,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> dict:
    try:
        store, _terminal = PedeOnEdgeService(db).authorize_checkout(payload)
        return PedeOnCheckoutService(db).checkout(store, order_id, payload)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/edge/register", response_model=EdgeNodeRead)
def register_edge(
    payload: EdgeRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
    _: User = Depends(require_pedeon_activation_owner),
) -> EdgeNodeRead:
    try:
        return PedeOnEdgeService(db).register(
            payload, request.client.host if request.client else None
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/edge/{node_key}/heartbeat", response_model=EdgeNodeRead)
def edge_heartbeat(
    node_key: str,
    payload: EdgeHeartbeatRequest,
    request: Request,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> EdgeNodeRead:
    try:
        return PedeOnEdgeService(db).heartbeat(
            node_key, payload, request.client.host if request.client else None
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/edge/catalog", response_model=EdgeCatalogRead)
def edge_catalog(
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> EdgeCatalogRead:
    try:
        store = PedeOnEdgeService(db).authorize_catalog(terminal_key)
        return PedeOnPublicCatalogService.edge_catalog(db, store)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/edge/catalog/operational", response_model=EdgeCatalogRead)
def operational_edge_catalog(
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> EdgeCatalogRead:
    try:
        store = PedeOnEdgeService(db).authorize_catalog(terminal_key)
        return PedeOnPublicCatalogService.operational_catalog(db, store)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/edge/catalog/revision")
def edge_catalog_revision(
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> dict[str, int]:
    try:
        store = PedeOnEdgeService(db).authorize_catalog(terminal_key)
        return {"revision": PedeOnPublicCatalogService.operational_catalog_revision(db, store)}
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/edge/authorize-terminal", response_model=EdgeTerminalAuthorizationRead)
def edge_authorize_terminal(
    payload: EdgeTerminalAuthorizeRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> EdgeTerminalAuthorizationRead:
    try:
        return PedeOnEdgeService(db).authorize_terminal(payload)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/public/{slug}", response_model=PublicCatalogPageRead)
def public_catalog(
    slug: str,
    search: str = Query(default="", max_length=120),
    category: str | None = Query(default=None, max_length=100),
    product_id: int | None = Query(default=None, ge=1),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=24, ge=1, le=40),
) -> PublicCatalogPageRead:
    try:
        return PedeOnPublicCatalogService.catalog(
            slug,
            search=search,
            category=category,
            product_id=product_id,
            page=page,
            page_size=page_size,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/public/{slug}/quote", response_model=CartQuoteRead)
def public_cart_quote(slug: str, payload: CartQuoteRequest) -> CartQuoteRead:
    try:
        return PedeOnPublicCatalogService.quote(slug, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/public/{slug}/orders", response_model=PublicOrderRead, status_code=201)
def create_public_order(
    slug: str, payload: PublicOrderCreate, request: Request, response: Response
) -> PublicOrderRead:
    try:
        registry = PedeOnPublicCatalogService._registry(slug)
        with session_for_company(registry.company_code) as customer_db:
            store = customer_db.get(PedeOnStore, registry.tenant_store_id)
            if store is None:
                raise LookupError("Loja PedeOn não encontrada.")
            customer = read_customer(request, customer_db, store, registry.company_code)
            payload.customer_name = customer.name
            payload.customer_email = customer.email
            if customer.phone:
                payload.customer_phone = customer.phone
            if payload.customer_document is not None:
                customer.document_number = payload.customer_document.strip() or None
            if payload.delivery_address is not None:
                customer.delivery_address = payload.delivery_address.model_dump()
            customer_db.commit()
            update_global_profile(customer)
        return PedeOnPublicOrderService.create(slug, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/public/{slug}/auth/register", response_model=PublicCustomerAuthRead)
def register_public_customer(
    slug: str, payload: PublicCustomerAuthInput, request: Request, response: Response
) -> dict:
    registry = PedeOnPublicCatalogService._registry(slug)
    email = normalize_email(payload.email)
    if payload.name is None:
        raise HTTPException(status_code=422, detail="Informe seu nome.")
    with session_for_company(registry.company_code) as db:
        store = db.get(PedeOnStore, registry.tenant_store_id)
        if store is None:
            raise HTTPException(status_code=404, detail="Loja PedeOn não encontrada.")
        existing = db.scalar(select(PedeOnCustomer).where(
            PedeOnCustomer.store_id == store.id, PedeOnCustomer.email == email
        ))
        if existing is not None and existing.global_customer_id is None:
            raise HTTPException(status_code=409, detail="Já existe uma conta com este e-mail.")
        global_customer = global_customer_for(
            email=email,
            name=payload.name,
            phone=payload.phone,
            password_hash=hash_password(payload.password),
        )
        if not global_customer.active:
            raise HTTPException(status_code=403, detail="Esta conta de cliente está bloqueada.")
        customer = attach_local_customer(db, store, registry.company_code, global_customer)
        db.commit()
        db.refresh(customer)
        token = token_for(customer, slug)
        set_customer_cookie(response, request, token)
        return public_customer(customer, token)


@router.post("/public/{slug}/auth/login", response_model=PublicCustomerAuthRead)
def login_public_customer(
    slug: str, payload: PublicCustomerAuthInput, request: Request, response: Response
) -> dict:
    registry = PedeOnPublicCatalogService._registry(slug)
    email = normalize_email(payload.email)
    with session_for_company(registry.company_code) as db:
        store = db.get(PedeOnStore, registry.tenant_store_id)
        local_customer = db.scalar(select(PedeOnCustomer).where(
            PedeOnCustomer.store_id == (store.id if store else -1),
            PedeOnCustomer.email == email,
            PedeOnCustomer.active.is_(True),
        ))
        from app.models.master_pedeon_customer import MasterPedeOnCustomer
        with MasterSessionLocal() as master_db:
            global_customer = master_db.scalar(
                select(MasterPedeOnCustomer).where(MasterPedeOnCustomer.email == email)
            )
        password_hash = (
            global_customer.password_hash if global_customer else None
        ) or (local_customer.password_hash if local_customer else None)
        if store is None or not password_hash or not verify_password(payload.password, password_hash):
            raise HTTPException(status_code=401, detail="E-mail ou senha inválidos.")
        if global_customer is None:
            global_customer = global_customer_for(
                email=email,
                name=local_customer.name if local_customer else email,
                phone=local_customer.phone if local_customer else None,
                password_hash=password_hash,
            )
        if not global_customer.active:
            raise HTTPException(status_code=403, detail="Esta conta de cliente está bloqueada.")
        customer = attach_local_customer(db, store, registry.company_code, global_customer)
        db.commit()
        token = token_for(customer, slug)
        set_customer_cookie(response, request, token)
        return public_customer(customer, token)


@router.get("/public/{slug}/auth/me", response_model=PublicCustomerAuthRead)
def current_public_customer(slug: str, request: Request, response: Response) -> dict:
    registry = PedeOnPublicCatalogService._registry(slug)
    with session_for_company(registry.company_code) as db:
        store = db.get(PedeOnStore, registry.tenant_store_id)
        if store is None:
            raise HTTPException(status_code=404, detail="Loja PedeOn não encontrada.")
        customer = read_customer(request, db, store, registry.company_code)
        token = token_for(customer, slug)
        set_customer_cookie(response, request, token)
        return public_customer(customer, token)


@router.put("/public/{slug}/auth/profile", response_model=PublicCustomerAuthRead)
def update_public_customer_profile(
    slug: str, payload: PublicCustomerProfileUpdate, request: Request, response: Response
) -> dict:
    registry = PedeOnPublicCatalogService._registry(slug)
    with session_for_company(registry.company_code) as db:
        store = db.get(PedeOnStore, registry.tenant_store_id)
        if store is None:
            raise HTTPException(status_code=404, detail="Loja PedeOn não encontrada.")
        customer = read_customer(request, db, store, registry.company_code)
        customer.document_number = (payload.document or "").strip() or None
        customer.delivery_address = (
            payload.delivery_address.model_dump()
            if payload.delivery_address is not None
            else None
        )
        db.commit()
        db.refresh(customer)
        update_global_profile(customer)
        token = token_for(customer, slug)
        set_customer_cookie(response, request, token)
        return public_customer(customer, token)


@router.post("/public/{slug}/auth/logout")
def logout_public_customer(slug: str, request: Request, response: Response) -> dict:
    clear_customer_cookie(response, request)
    return {"ok": True}


@router.get("/public/{slug}/auth/{provider}/start")
def start_public_social_login(slug: str, provider: str, request: Request) -> dict:
    if provider not in {"google", "facebook", "apple"}:
        raise HTTPException(status_code=404, detail="Provedor de acesso não suportado.")
    if provider != "google":
        raise HTTPException(
            status_code=501,
            detail=f"O acesso com {provider.title()} ainda não foi habilitado nesta loja.",
        )
    with MasterSessionLocal() as master_db:
        config = next(
            (item for item in get_configs(master_db) if item.provider == provider),
            None,
        )
    if config is None or not config.enabled or not config.configured:
        raise HTTPException(
            status_code=503,
            detail="O login Google ainda não está configurado nas credenciais da plataforma.",
        )
    now = time.time()
    _SOCIAL_STATES.clear()
    state = secrets.token_urlsafe(32)
    origin = request.headers.get("origin") or request.headers.get("referer")
    if origin:
        parsed_origin = urlparse(origin)
        if parsed_origin.scheme and parsed_origin.netloc:
            origin = f"{parsed_origin.scheme}://{parsed_origin.netloc}"
        else:
            origin = origin.rstrip("/")
    else:
        origin = public_store_url(slug, get_settings().pedeon_public_base_url)
        if origin.endswith("/cardapio"):
            origin = origin.removesuffix("/cardapio")
    _SOCIAL_STATES[state] = (slug, now + _SOCIAL_STATE_TTL_SECONDS, origin)
    return {
        "authorization_url": "https://accounts.google.com/o/oauth2/v2/auth?"
        + urlencode(
            {
                "client_id": config.client_id,
                "redirect_uri": config.redirect_uri,
                "response_type": "code",
                "scope": "openid email profile",
                "state": state,
                "prompt": "select_account",
            }
        )
    }


@router.get("/public/auth/google/callback")
def public_google_callback(
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
) -> RedirectResponse:
    state_data = _SOCIAL_STATES.pop(state or "", None)
    if state_data is None or state_data[1] < time.time():
        raise HTTPException(status_code=400, detail="Sessão OAuth expirada ou inválida.")
    slug, _expires_at, public_origin = state_data
    if error or not code:
        raise HTTPException(status_code=400, detail="O login Google foi cancelado.")
    with MasterSessionLocal() as master_db:
        config = next(
            (item for item in get_configs(master_db) if item.provider == "google"),
            None,
        )
    if config is None or not config.enabled or not config.configured:
        raise HTTPException(status_code=503, detail="Login Google não configurado.")
    try:
        token_response = requests.post(
            "https://oauth2.googleapis.com/token",
            data={
                "code": code,
                "client_id": config.client_id,
                "client_secret": config.client_secret,
                "redirect_uri": config.redirect_uri,
                "grant_type": "authorization_code",
            },
            timeout=15,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail="Não foi possível comunicar com o Google durante o login.",
        ) from exc
    if not token_response.ok:
        raise HTTPException(status_code=400, detail="O Google não autorizou este login.")
    id_token = token_response.json().get("id_token")
    if not id_token:
        raise HTTPException(status_code=400, detail="Resposta OAuth do Google sem identidade.")
    try:
        profile_response = requests.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": id_token},
            timeout=15,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail="Não foi possível validar a conta Google neste momento.",
        ) from exc
    if not profile_response.ok:
        raise HTTPException(status_code=400, detail="Não foi possível validar a conta Google.")
    profile = profile_response.json()
    if profile.get("aud") != config.client_id or profile.get("email_verified") not in {True, "true", "True"}:
        raise HTTPException(status_code=400, detail="A conta Google não pôde ser validada.")
    registry = PedeOnPublicCatalogService._registry(slug)
    with session_for_company(registry.company_code) as db:
        store = db.get(PedeOnStore, registry.tenant_store_id)
        email = normalize_email(profile.get("email", ""))
        if store is None or not email:
            raise HTTPException(status_code=404, detail="Loja ou e-mail Google não encontrado.")
        global_customer = global_customer_for(
            email=email,
            name=profile.get("name") or email.split("@", 1)[0],
            provider="google",
            provider_subject=profile.get("sub"),
        )
        if not global_customer.active:
            raise HTTPException(status_code=403, detail="Esta conta de cliente está bloqueada.")
        customer = attach_local_customer(
            db, store, registry.company_code, global_customer
        )
        db.commit()
        db.refresh(customer)
        handoff_code = secrets.token_urlsafe(32)
        _SOCIAL_CODES[handoff_code] = (
            slug,
            customer.id,
            token_for(customer, slug),
            time.time() + _SOCIAL_CODE_TTL_SECONDS,
        )
    return RedirectResponse(
        url=f"{public_origin}{public_store_path(public_origin, slug)}?social_code={handoff_code}",
        status_code=303,
    )


@router.post("/public/{slug}/auth/google/exchange", response_model=PublicCustomerAuthRead)
def exchange_public_google_code(
    slug: str, payload: dict, request: Request, response: Response
):
    handoff_code = str(payload.get("code", ""))
    code_data = _SOCIAL_CODES.pop(handoff_code, None)
    if code_data is None or code_data[3] < time.time() or code_data[0] != slug:
        raise HTTPException(status_code=400, detail="Código de login Google expirado ou inválido.")
    registry = PedeOnPublicCatalogService._registry(slug)
    with session_for_company(registry.company_code) as db:
        customer = db.get(PedeOnCustomer, code_data[1])
        if customer is None or not customer.active:
            raise HTTPException(status_code=401, detail="Conta Google indisponível.")
        set_customer_cookie(response, request, code_data[2])
        return public_customer(customer, code_data[2])


@router.get("/public/{slug}/orders/{tracking_token}", response_model=PublicOrderRead)
def track_public_order(slug: str, tracking_token: str) -> PublicOrderRead:
    try:
        return PedeOnPublicOrderService.track(slug, tracking_token)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/public/{slug}/payments/infinitepay/webhook")
def infinitepay_webhook(slug: str, payload: dict) -> dict:
    try:
        return PedeOnPublicOrderService.process_infinitepay_webhook(slug, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (ValueError, requests.RequestException) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/orders", response_model=OrderPageRead)
def list_orders(
    order_status: str | None = Query(default=None, alias="status", max_length=40),
    source: str | None = Query(default=None, max_length=40),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:orders")),
) -> OrderPageRead:
    try:
        return PedeOnOrderService(db).list(order_status, source, page, page_size)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/orders/{order_id}", response_model=OrderDetailRead)
def get_order(
    order_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:orders")),
) -> OrderDetailRead:
    try:
        return PedeOnOrderService(db).detail(order_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.patch("/orders/{order_id}/status", response_model=OrderDetailRead)
def update_order_status(
    order_id: int,
    payload: OrderStatusUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("pedeon:orders")),
) -> OrderDetailRead:
    try:
        return PedeOnOrderService(db).transition(order_id, payload.status, user.id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/orders/{order_id}/payments/confirm", response_model=OrderDetailRead)
def confirm_order_payment(
    order_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("pedeon:payments")),
) -> OrderDetailRead:
    try:
        return PedeOnOrderService(db).confirm_payment(order_id, user.id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/terminals/feed", response_model=TerminalFeedRead)
def terminal_order_feed(
    terminal_key: str = Query(min_length=16, max_length=180),
    after: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> TerminalFeedRead:
    try:
        return PedeOnTerminalService(db).feed(terminal_key, after, limit)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc


@router.get("/terminals/orders/{public_id}", response_model=OrderDetailRead)
def terminal_order_detail(
    public_id: str,
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> OrderDetailRead:
    try:
        return PedeOnTerminalService(db).order_detail(terminal_key, public_id)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.patch("/terminals/orders/{public_id}/status", response_model=OrderDetailRead)
def terminal_update_order_status(
    public_id: str,
    payload: OrderStatusUpdate,
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> OrderDetailRead:
    try:
        return PedeOnTerminalService(db).transition(
            terminal_key, public_id, payload.status
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/terminals/print-jobs", response_model=list[TerminalPrintJobRead])
def terminal_print_jobs(
    terminal_key: str = Query(min_length=16, max_length=180),
    limit: int = Query(default=10, ge=1, le=25),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> list[TerminalPrintJobRead]:
    try:
        return PedeOnTerminalService(db).claim_print_jobs(terminal_key, limit)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc


@router.patch(
    "/terminals/print-jobs/{job_id}", response_model=TerminalPrintJobRead
)
def terminal_finish_print_job(
    job_id: int,
    payload: TerminalPrintJobResult,
    terminal_key: str = Query(min_length=16, max_length=180),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("sales:create")),
) -> TerminalPrintJobRead:
    try:
        return PedeOnTerminalService(db).finish_print_job(
            terminal_key, job_id, payload.status, payload.error
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/catalog", response_model=CatalogPageRead)
def list_catalog(
    search: str = Query(default="", max_length=120),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=20),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> CatalogPageRead:
    try:
        return PedeOnCatalogService(db).list_catalog(search, page, page_size)
    except LookupError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/catalog/categories", response_model=CategoryRead, status_code=201)
def create_category(
    payload: CategoryCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> CategoryRead:
    return PedeOnCatalogService(db).create_category(payload)


@router.put("/catalog/categories/{category_id}", response_model=CategoryRead)
def update_category(
    category_id: int,
    payload: CategoryUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> CategoryRead:
    try:
        return PedeOnCatalogService(db).update_category(category_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.put("/catalog/categories-order", response_model=list[CategoryRead])
def reorder_categories(
    payload: CategoryReorder,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> list[CategoryRead]:
    try:
        return PedeOnCatalogService(db).reorder_categories(payload)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.delete("/catalog/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(
    category_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> Response:
    try:
        PedeOnCatalogService(db).delete_category(category_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/catalog/modifier-groups",
    response_model=ModifierGroupRead,
    status_code=status.HTTP_201_CREATED,
)
def create_modifier_group(
    payload: ModifierGroupInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> ModifierGroupRead:
    try:
        return PedeOnCatalogService(db).create_modifier_group(payload)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put(
    "/catalog/modifier-groups/{group_id}", response_model=ModifierGroupRead
)
def update_modifier_group(
    group_id: int,
    payload: ModifierGroupInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> ModifierGroupRead:
    try:
        return PedeOnCatalogService(db).update_modifier_group(group_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.delete(
    "/catalog/modifier-groups/{group_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_modifier_group(
    group_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> Response:
    try:
        PedeOnCatalogService(db).delete_modifier_group(group_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/catalog/products/{product_id}", response_model=CatalogProductRead)
def update_publication(
    product_id: int,
    payload: PublicationUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:catalog")),
) -> CatalogProductRead:
    try:
        return PedeOnCatalogService(db).update_publication(product_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/settings", response_model=PedeOnSettingsRead)
def get_settings(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:view")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).get_settings()


@router.put("/settings/store", response_model=PedeOnSettingsRead)
def update_store(
    payload: StoreSettingsUpdate,
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    _: User = Depends(require_permission("pedeon:settings")),
) -> PedeOnSettingsRead:
    token_payload = decode_access_token(credentials.credentials)
    company_code = str(token_payload.get("company_code") or "").strip()
    if not company_code:
        raise HTTPException(status_code=403, detail="Empresa não identificada.")
    try:
        return PedeOnSettingsService(db).update_store(company_code, payload)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/settings/media/{media_type}", response_model=PedeOnSettingsRead)
async def upload_store_media(
    media_type: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> PedeOnSettingsRead:
    if media_type not in {"logo", "cover"}:
        raise HTTPException(status_code=400, detail="Tipo de imagem inválido.")
    service = PedeOnSettingsService(db)
    store = service._ensure_store()
    url = await save_public_image(file, f"pedeon-store-{store.id}")
    if media_type == "logo":
        store.logo_url = url
    else:
        store.cover_url = url
    db.commit()
    return service.get_settings()


@router.put("/settings/payments/manual-pix", response_model=PedeOnSettingsRead)
def update_manual_pix(
    payload: ManualPixUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:payments")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).update_manual_pix(payload)


@router.put("/settings/payments/infinitepay", response_model=PedeOnSettingsRead)
def update_infinitepay(
    payload: InfinitePayUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:payments")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).update_infinitepay(payload)


@router.put("/settings/payments/delivery-card", response_model=PedeOnSettingsRead)
def update_delivery_card(
    payload: DeliveryCardUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:payments")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).update_delivery_card(payload)


@router.put("/settings/payments/pickup-payment", response_model=PedeOnSettingsRead)
def update_pickup_payment(
    payload: PickupPaymentUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:payments")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).update_pickup_payment(payload)


@router.put("/settings/delivery", response_model=PedeOnSettingsRead)
def update_delivery_operation(
    payload: DeliveryOperationUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> PedeOnSettingsRead:
    return PedeOnSettingsService(db).update_delivery_operation(payload)


@router.post(
    "/settings/delivery-zones",
    response_model=DeliveryZoneRead,
    status_code=status.HTTP_201_CREATED,
)
def create_delivery_zone(
    payload: DeliveryZoneInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> DeliveryZoneRead:
    try:
        return PedeOnSettingsService(db).create_delivery_zone(payload)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put("/settings/delivery-zones/{zone_id}", response_model=DeliveryZoneRead)
def update_delivery_zone(
    zone_id: int,
    payload: DeliveryZoneInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> DeliveryZoneRead:
    try:
        return PedeOnSettingsService(db).update_delivery_zone(zone_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.delete(
    "/settings/delivery-zones/{zone_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_delivery_zone(
    zone_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> Response:
    try:
        PedeOnSettingsService(db).delete_delivery_zone(zone_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/settings/stations",
    response_model=FulfillmentStationRead,
    status_code=status.HTTP_201_CREATED,
)
def create_fulfillment_station(
    payload: FulfillmentStationInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> FulfillmentStationRead:
    try:
        return PedeOnSettingsService(db).create_station(payload)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put(
    "/settings/stations/{station_id}", response_model=FulfillmentStationRead
)
def update_fulfillment_station(
    station_id: int,
    payload: FulfillmentStationInput,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:settings")),
) -> FulfillmentStationRead:
    try:
        return PedeOnSettingsService(db).update_station(station_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put("/settings/terminals/{terminal_id}", response_model=PedeOnSettingsRead)
def update_terminal(
    terminal_id: int,
    payload: TerminalPermissionUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission("pedeon:terminals")),
) -> PedeOnSettingsRead:
    try:
        return PedeOnSettingsService(db).update_terminal(terminal_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

from fastapi import APIRouter

from app.api.routes import (
    auth,
    admin,
    cash_closings,
    clients,
    dashboard,
    equipments,
    fiscal,
    fiscal_assistant,
    health,
    master_dashboard,
    master_billing,
    master_contact_requests,
    master_access,
    master_integrations,
    master_plans,
    master_companies,
    monitoring,
    master_payment_settings,
    master_pdv_terminals,
    master_pdv_updates,
    master_segments,
    master_staff,
    master_support,
    marketplaces,
    payables,
    pdv_operators,
    pdv_cash_sessions,
    pdv_sync,
    pdv_terminals,
    products,
    production_orders,
    receivables,
    sales,
    service_contracts,
    service_orders,
    site,
    stock_entries,
    tickets,
    uploads,
    xml_inbox,
)

api_router = APIRouter()
api_router.include_router(health.router, tags=["health"])
api_router.include_router(site.router, prefix="/site", tags=["site"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(master_companies.router, prefix="/master", tags=["master"])
api_router.include_router(master_dashboard.router, prefix="/master", tags=["master"])
api_router.include_router(master_billing.router, prefix="/master", tags=["master"])
api_router.include_router(master_contact_requests.router, prefix="/master", tags=["master"])
api_router.include_router(master_access.router, prefix="/master", tags=["master"])
api_router.include_router(master_integrations.router, prefix="/master", tags=["master"])
api_router.include_router(master_plans.router, prefix="/master", tags=["master"])
api_router.include_router(master_segments.router, prefix="/master", tags=["master"])
api_router.include_router(master_payment_settings.router, prefix="/master", tags=["master"])
api_router.include_router(master_pdv_terminals.router, prefix="/master", tags=["master"])
api_router.include_router(master_pdv_updates.router, prefix="/master", tags=["master"])
api_router.include_router(master_staff.router, prefix="/master", tags=["master"])
api_router.include_router(master_support.router, tags=["support"])
api_router.include_router(clients.router, prefix="/clients", tags=["clients"])
api_router.include_router(equipments.router, prefix="/equipments", tags=["equipments"])
api_router.include_router(tickets.router, prefix="/tickets", tags=["tickets"])
api_router.include_router(monitoring.router, prefix="/monitoring", tags=["monitoring"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
api_router.include_router(uploads.router, prefix="/uploads", tags=["uploads"])
api_router.include_router(products.router, prefix="/products", tags=["products"])
api_router.include_router(stock_entries.router, prefix="/stock", tags=["stock"])
api_router.include_router(xml_inbox.router, prefix="/xml-inbox", tags=["xml-inbox"])
api_router.include_router(production_orders.router, prefix="/production-orders", tags=["production-orders"])
api_router.include_router(fiscal.router, prefix="/fiscal", tags=["fiscal"])
api_router.include_router(
    fiscal_assistant.router,
    prefix="/fiscal-assistant",
    tags=["fiscal-assistant"],
)
api_router.include_router(pdv_operators.router, prefix="/pdv", tags=["pdv"])
api_router.include_router(pdv_cash_sessions.router, prefix="/pdv", tags=["pdv"])
api_router.include_router(pdv_sync.router, prefix="/pdv", tags=["pdv-sync"])
api_router.include_router(pdv_terminals.router, prefix="/pdv", tags=["pdv"])
api_router.include_router(cash_closings.router, prefix="/pdv", tags=["pdv"])
api_router.include_router(sales.router, prefix="/sales", tags=["sales"])
api_router.include_router(marketplaces.router, prefix="/marketplaces", tags=["marketplaces"])
api_router.include_router(
    service_contracts.router,
    prefix="/service-contracts",
    tags=["service-contracts"],
)
api_router.include_router(receivables.router, prefix="/receivables", tags=["receivables"])
api_router.include_router(payables.router, prefix="/payables", tags=["payables"])
api_router.include_router(
    service_orders.router,
    prefix="/service-orders",
    tags=["service-orders"],
)

from pathlib import Path

import truststore
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.router import api_router
from app.core.config import get_settings
from app.services.tenancy import seed_default_company
from app.services.fiscal_queue import fiscal_queue_worker
from app.services.billing_automation import billing_automation_worker

settings = get_settings()

truststore.inject_into_ssl()

app = FastAPI(title=settings.app_name)


def _validate_production_configuration() -> None:
    if settings.app_env.lower() not in {"production", "prod"}:
        return
    unsafe_values = {
        "change-me",
        "change-me-xml-inbound",
        "",
    }
    if settings.secret_key in unsafe_values or len(settings.secret_key) < 32:
        raise RuntimeError(
            "SECRET_KEY de producao ausente ou insegura; configure um segredo aleatorio de pelo menos 32 caracteres."
        )
    if settings.xml_inbound_secret in unsafe_values or len(settings.xml_inbound_secret) < 32:
        raise RuntimeError(
            "XML_INBOUND_SECRET de producao ausente ou inseguro; configure um segredo aleatorio de pelo menos 32 caracteres."
        )
    if settings.master_admin_password in unsafe_values or settings.master_admin_password == "AUAEGP8bDq_Xees5t%":
        raise RuntimeError(
            "MASTER_ADMIN_PASSWORD de producao ainda usa o valor padrao; configure a credencial fora do codigo."
        )

upload_dir = Path(__file__).resolve().parents[2] / "uploads"
upload_dir.mkdir(parents=True, exist_ok=True)
app.mount("/public", StaticFiles(directory=str(upload_dir)), name="public")


@app.on_event("startup")
def startup_seed_master_company() -> None:
    _validate_production_configuration()
    seed_default_company()
    fiscal_queue_worker.start()
    billing_automation_worker.start()


@app.on_event("shutdown")
def shutdown_fiscal_queue_worker() -> None:
    billing_automation_worker.stop()
    fiscal_queue_worker.stop()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in settings.cors_origins.split(",")
        if origin.strip()
    ],
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Accept",
        "Authorization",
        "Content-Type",
        "Origin",
        "X-CSRF-Token",
        "X-Requested-With",
    ],
    expose_headers=["X-CSRF-Token"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault(
        "Permissions-Policy", "camera=(), microphone=(), geolocation=()"
    )
    if settings.app_env.lower() in {"production", "prod"}:
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
    return response


app.include_router(api_router)

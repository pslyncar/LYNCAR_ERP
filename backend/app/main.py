from pathlib import Path

import truststore
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.router import api_router
from app.core.config import get_settings
from app.services.tenancy import seed_default_company

settings = get_settings()

truststore.inject_into_ssl()

app = FastAPI(title=settings.app_name)

upload_dir = Path(__file__).resolve().parents[2] / "uploads"
upload_dir.mkdir(parents=True, exist_ok=True)
app.mount("/public", StaticFiles(directory=str(upload_dir)), name="public")


@app.on_event("startup")
def startup_seed_master_company() -> None:
    seed_default_company()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in settings.cors_origins.split(",")
        if origin.strip()
    ],
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(api_router)

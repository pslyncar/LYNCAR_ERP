from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "PapezzoSync API"
    app_env: str = "development"
    database_url: str = (
        "postgresql+psycopg://postgres:postgres@localhost:5432/papezzosync"
    )
    master_database_url: str | None = None
    secret_key: str = "change-me"
    access_token_expire_minutes: int = 60
    default_company_code: str = "papezzosync"
    default_company_name: str = "PapezzoSync"
    master_company_code: str = "master"
    master_company_name: str = "PapezzoSync Master"
    master_admin_email: str = "admin@papezzosync.com.br"
    master_admin_password: str = "AUAEGP8bDq_Xees5t%"
    mercado_pago_public_key: str | None = "TEST-7407e8bb-8ef1-4e68-a91c-4f0f11a1af19"
    mercado_pago_access_token: str | None = None
    mercado_pago_webhook_url: str | None = None
    mercado_livre_client_id: str | None = None
    mercado_livre_client_secret: str | None = None
    mercado_livre_redirect_uri: str | None = None
    holiday_sync_enabled: bool = True
    feriados_api_token: str | None = None
    sefaz_tls_verify: bool = True
    sefaz_timeout_seconds: int = 120
    xml_inbound_domain: str = "notas.lyncar.com.br"
    xml_inbound_secret: str = "change-me-xml-inbound"
    xml_inbound_max_bytes: int = 5_000_000
    cors_origins: str = "http://localhost:3000,http://localhost:8080,http://localhost:5000,http://127.0.0.1:3000,http://127.0.0.1:8080,http://127.0.0.1:5000"
    cors_origin_regex: str | None = (
        r"https://(([a-z0-9-]+\.)?erp\.)?lyncar\.com\.br|http://(localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3})(:\d+)?"
    )

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if settings.master_database_url is None:
        settings.master_database_url = settings.database_url
    return settings

from urllib.parse import urlparse


def public_store_url(slug: str, configured_base: str) -> str:
    """Monta a URL pública sem permitir que o tenant escolha o domínio Lyncar."""
    base = configured_base.rstrip("/")
    if "{slug}" in base:
        return base.replace("{slug}", slug)
    host = (urlparse(base).hostname or "").lower()
    if host in {"lyncar.com.br", "pedeon.lyncar.com.br"}:
        return f"https://{slug}.lyncar.com.br/cardapio"
    return f"{base}/{slug}"


def public_store_path(origin: str, slug: str) -> str:
    host = (urlparse(origin).hostname or "").lower()
    suffix = ".lyncar.com.br"
    subdomain = host[: -len(suffix)] if host.endswith(suffix) else ""
    if (
        subdomain
        and "." not in subdomain
        and subdomain not in {"www", "api", "pedeon"}
    ):
        return "/cardapio"
    return f"/{slug}"

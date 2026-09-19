"""Pesquisa externa controlada para a Lyna, somente sob demanda."""

from __future__ import annotations

import json
from dataclasses import dataclass
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

_TRIGGERS = ("pesquise", "pesquisar", "pesquisa", "novidade", "atual", "vigente", "recente", "mudou", "mudanca", "noticia", "hoje", "ultima", "fonte oficial", "consulta oficial")
_TOPICS = ("nfe", "nf-e", "nfce", "nfc-e", "nfse", "nfs-e", "sefaz", "confaz", "receita", "fiscal", "tribut", "ibs", "cbs", "ncm", "cest", "cfop", "cst", "csosn", "simples nacional", "mei", "certificado digital", "nota fiscal", "reforma tributaria", "debian", "postgres", "postgresql", "fastapi", "flutter", "cloudflare", "lyncar", "pedeon")


@dataclass(frozen=True)
class ResearchResult:
    title: str
    url: str
    snippet: str
    published: str = ""


@dataclass(frozen=True)
class ResearchResponse:
    status: str
    category: str = ""
    results: tuple[ResearchResult, ...] = ()
    message: str = ""


def _normalize(value: str) -> str:
    return (value.lower().replace("ç", "c").replace("ã", "a").replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u"))


def should_search(message: str) -> bool:
    normalized = _normalize(message)
    return any(term in normalized for term in _TRIGGERS) and any(term in normalized for term in _TOPICS)


def category_for(message: str) -> str:
    normalized = _normalize(message)
    if "nfse" in normalized or "nfs-e" in normalized:
        return "nfse"
    if "ncm" in normalized or "cest" in normalized:
        return "ncm"
    if any(term in normalized for term in ("nfe", "nf-e", "nfce", "nfc-e", "sefaz", "confaz")):
        return "fiscal_updates"
    if any(term in normalized for term in ("debian", "postgres", "postgresql", "fastapi", "flutter", "cloudflare")):
        return "infrastructure"
    return "fiscal_legislation"


def _domains(category: str) -> tuple[str, ...]:
    official = ("gov.br", "fazenda.gov.br", "nfe.fazenda.gov.br", "confaz.fazenda.gov.br")
    if category == "infrastructure":
        return official + ("debian.org", "postgresql.org", "fastapi.tiangolo.com", "flutter.dev", "cloudflare.com")
    return official


def _safe_url(value: str, domains: tuple[str, ...]) -> bool:
    parsed = urlparse(value)
    host = (parsed.hostname or "").lower().rstrip(".")
    return parsed.scheme == "https" and any(host == domain or host.endswith("." + domain) for domain in domains)


def search(message: str, *, enabled: bool, base_url: str | None, timeout: int = 8, max_results: int = 5) -> ResearchResponse:
    if not should_search(message):
        return ResearchResponse(status="not_requested")
    category = category_for(message)
    if not enabled or not base_url:
        return ResearchResponse(status="unavailable", category=category, message="Pesquisa externa não configurada neste ambiente.")
    params = {"q": f"{message.strip()} Lyncar legislação oficial", "format": "json", "language": "pt-BR", "categories": "news,general"}
    request = Request(base_url.rstrip("/") + "/search?" + urlencode(params), headers={"Accept": "application/json"})
    try:
        with urlopen(request, timeout=max(2, min(timeout, 15))) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, TimeoutError, ValueError, json.JSONDecodeError):
        return ResearchResponse(status="unavailable", category=category, message="A pesquisa externa não respondeu.")
    results: list[ResearchResult] = []
    for item in payload.get("results", []):
        if not isinstance(item, dict):
            continue
        url = str(item.get("url") or "")
        if not _safe_url(url, _domains(category)):
            continue
        results.append(ResearchResult(str(item.get("title") or "Fonte oficial"), url, str(item.get("content") or item.get("snippet") or "")[:500], str(item.get("publishedDate") or item.get("published") or "")))
        if len(results) >= max(1, min(max_results, 8)):
            break
    if not results:
        return ResearchResponse(status="empty", category=category, message="Nenhuma fonte oficial segura foi encontrada.")
    return ResearchResponse(status="ok", category=category, results=tuple(results))


def format_for_prompt(response: ResearchResponse) -> str:
    if response.status == "not_requested":
        return "Pesquisa externa não solicitada; não consulte a internet."
    if response.status != "ok":
        return response.message or "Não há pesquisa externa disponível."
    lines = ["Fontes externas oficiais encontradas sob demanda:"]
    for result in response.results:
        date = f" | data: {result.published}" if result.published else ""
        lines.append(f"- {result.title}{date}\n  URL: {result.url}\n  Resumo: {result.snippet}")
    return "\n".join(lines)

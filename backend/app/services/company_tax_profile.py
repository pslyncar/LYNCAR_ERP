from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def only_digits(value: str | None) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def clean_text(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def normalize_bool(value) -> bool | None:
    if isinstance(value, bool):
        return value
    if value is None:
        return None
    text = str(value).strip().lower()
    if text in {"sim", "s", "true", "1", "yes"}:
        return True
    if text in {"nao", "não", "n", "false", "0", "no"}:
        return False
    return None


@dataclass
class TaxProfileLookupResult:
    cnpj: str
    found: bool = False
    source: str | None = None
    status: str = "not_found"
    message: str | None = None
    legal_name: str | None = None
    trade_name: str | None = None
    tax_regime: str | None = None
    crt: str | None = None
    is_mei: bool | None = None
    is_simples: bool | None = None
    cnae_main: str | None = None
    cnae_description: str | None = None
    legal_nature: str | None = None
    company_size: str | None = None
    status_reason: str | None = None
    opened_at: str | None = None
    email: str | None = None
    phone: str | None = None
    zip_code: str | None = None
    state: str | None = None
    city: str | None = None
    city_code: str | None = None
    neighborhood: str | None = None
    address_line: str | None = None
    address_number: str | None = None
    address_complement: str | None = None

    def as_dict(self) -> dict:
        return {
            "cnpj": self.cnpj,
            "found": self.found,
            "source": self.source,
            "status": self.status,
            "message": self.message,
            "legal_name": self.legal_name,
            "trade_name": self.trade_name,
            "tax_regime": self.tax_regime,
            "crt": self.crt,
            "is_mei": self.is_mei,
            "is_simples": self.is_simples,
            "cnae_main": self.cnae_main,
            "cnae_description": self.cnae_description,
            "legal_nature": self.legal_nature,
            "company_size": self.company_size,
            "status_reason": self.status_reason,
            "opened_at": self.opened_at,
            "email": self.email,
            "phone": self.phone,
            "zip_code": self.zip_code,
            "state": self.state,
            "city": self.city,
            "city_code": self.city_code,
            "neighborhood": self.neighborhood,
            "address_line": self.address_line,
            "address_number": self.address_number,
            "address_complement": self.address_complement,
        }


def infer_regime(*, is_mei: bool | None, is_simples: bool | None, company_size: str | None) -> tuple[str | None, str | None]:
    if is_mei is True:
        return "mei", "4"
    if is_simples is True:
        return "simples_nacional", "1"
    size = (company_size or "").lower()
    if "mei" in size or "micro empreendedor" in size or "microempreendedor" in size:
        return "mei", "4"
    return None, None


def _extract_bool(data: dict, *keys: str) -> bool | None:
    for key in keys:
        if key in data:
            value = normalize_bool(data.get(key))
            if value is not None:
                return value
    return None


def _extract(data: dict, *keys: str) -> str | None:
    for key in keys:
        value = clean_text(data.get(key))
        if value:
            return value
    return None


def _nested(data: dict, *path: str):
    current = data
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _extract_nested_text(data: dict, *paths: tuple[str, ...]) -> str | None:
    for path in paths:
        value = clean_text(_nested(data, *path))
        if value:
            return value
    return None


def _first_activity(data: dict) -> dict:
    for key in ("atividade_principal", "atividade_principal", "cnae_fiscal_descricao"):
        value = data.get(key)
        if isinstance(value, list) and value and isinstance(value[0], dict):
            return value[0]
        if isinstance(value, dict):
            return value
    estabelecimento = data.get("estabelecimento")
    if isinstance(estabelecimento, dict):
        atividade = estabelecimento.get("atividade_principal")
        if isinstance(atividade, dict):
            return atividade
    return {}


def _normalize_cnae(value: str | None) -> str | None:
    digits = only_digits(value)
    return digits or clean_text(value)


def _get_json(url: str, *, timeout: int = 12) -> dict:
    request = Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "LyncarERP/1.0 fiscal-assistant",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8", errors="replace")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("Resposta da consulta CNPJ nao veio em objeto JSON.")
    return data


def _from_public_payload(cnpj: str, source: str, data: dict) -> TaxProfileLookupResult:
    estabelecimento = data.get("estabelecimento") if isinstance(data.get("estabelecimento"), dict) else {}
    activity = _first_activity(data)
    legal_name = _extract(data, "razao_social", "nome", "company_name", "legal_name")
    trade_name = _extract(data, "nome_fantasia", "fantasia", "alias", "trade_name") or clean_text(
        estabelecimento.get("nome_fantasia")
    )
    is_mei = _extract_bool(data, "opcao_pelo_mei", "mei", "is_mei")
    is_simples = _extract_bool(
        data,
        "opcao_pelo_simples",
        "simples",
        "simples_nacional",
        "is_simples",
    )
    company_size = _extract(data, "porte", "company_size", "descricao_porte")
    regime, crt = infer_regime(
        is_mei=is_mei,
        is_simples=is_simples,
        company_size=company_size,
    )
    message = (
        "Regime sugerido automaticamente. Conferir com o contador."
        if regime
        else "Consulta encontrou o CNPJ, mas nao confirmou regime gratuito. Informe manualmente."
    )
    return TaxProfileLookupResult(
        cnpj=cnpj,
        found=True,
        source=source,
        status="found",
        message=message,
        legal_name=legal_name,
        trade_name=trade_name,
        tax_regime=regime,
        crt=crt,
        is_mei=is_mei,
        is_simples=is_simples,
        cnae_main=_normalize_cnae(
            _extract(data, "cnae_fiscal", "cnae_principal", "main_activity_code")
            or clean_text(activity.get("code"))
            or clean_text(activity.get("codigo"))
        ),
        cnae_description=_extract(data, "cnae_fiscal_descricao")
        or clean_text(activity.get("text"))
        or clean_text(activity.get("descricao")),
        legal_nature=_extract(
            data,
            "natureza_juridica",
            "descricao_natureza_juridica",
            "legal_nature",
        )
        or _extract_nested_text(data, ("natureza_juridica", "descricao")),
        company_size=company_size,
        status_reason=_extract(data, "descricao_situacao_cadastral", "situacao", "status"),
        opened_at=_extract(data, "data_inicio_atividade", "abertura", "founded"),
        email=_extract(data, "email") or clean_text(estabelecimento.get("email")),
        phone=_extract(data, "telefone", "ddd_telefone_1")
        or clean_text(estabelecimento.get("telefone1"))
        or clean_text(estabelecimento.get("telefone")),
        zip_code=_extract(data, "cep") or clean_text(estabelecimento.get("cep")),
        state=_extract(data, "uf") or clean_text(estabelecimento.get("estado", {}).get("sigla") if isinstance(estabelecimento.get("estado"), dict) else None),
        city=_extract(data, "municipio") or _extract_nested_text(data, ("municipio", "descricao")) or clean_text(estabelecimento.get("cidade", {}).get("nome") if isinstance(estabelecimento.get("cidade"), dict) else None),
        city_code=_extract(data, "codigo_municipio_ibge", "municipio_ibge") or clean_text(estabelecimento.get("cidade", {}).get("ibge_id") if isinstance(estabelecimento.get("cidade"), dict) else None),
        neighborhood=_extract(data, "bairro") or clean_text(estabelecimento.get("bairro")),
        address_line=_extract(data, "logradouro") or clean_text(estabelecimento.get("logradouro")),
        address_number=_extract(data, "numero") or clean_text(estabelecimento.get("numero")),
        address_complement=_extract(data, "complemento") or clean_text(estabelecimento.get("complemento")),
    )


def lookup_company_tax_profile(cnpj_value: str | None) -> TaxProfileLookupResult:
    cnpj = only_digits(cnpj_value)
    if len(cnpj) != 14:
        return TaxProfileLookupResult(
            cnpj=cnpj,
            status="invalid_cnpj",
            message="Informe um CNPJ com 14 digitos para consultar.",
        )

    providers = [
        item.strip().lower()
        for item in os.getenv("LYNCAR_CNPJ_FREE_PROVIDERS", "brasilapi,cnpjws,receitaws,minhareceita").split(",")
        if item.strip()
    ]
    last_error: str | None = None
    for provider in providers:
        try:
            if provider == "brasilapi":
                data = _get_json(f"https://brasilapi.com.br/api/cnpj/v1/{cnpj}")
                return _from_public_payload(cnpj, "brasilapi", data)
            if provider == "cnpjws":
                data = _get_json(f"https://publica.cnpj.ws/cnpj/{cnpj}")
                return _from_public_payload(cnpj, "cnpjws", data)
            if provider == "receitaws":
                data = _get_json(f"https://receitaws.com.br/v1/cnpj/{cnpj}")
                return _from_public_payload(cnpj, "receitaws", data)
            if provider == "minhareceita":
                data = _get_json(f"https://minhareceita.org/{cnpj}")
                return _from_public_payload(cnpj, "minhareceita", data)
            custom_template = os.getenv(f"LYNCAR_CNPJ_PROVIDER_{provider.upper()}_URL")
            if custom_template:
                data = _get_json(custom_template.format(cnpj=cnpj))
                return _from_public_payload(cnpj, provider, data)
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
            last_error = str(exc)
            continue

    return TaxProfileLookupResult(
        cnpj=cnpj,
        status="not_found",
        message=(
            "Nao foi possivel confirmar o regime por consulta gratuita. "
            "Informe manualmente e confira com o contador."
            + (f" Ultimo retorno: {last_error}" if last_error else "")
        ),
    )


def apply_lookup_to_company(company, result: TaxProfileLookupResult) -> bool:
    company.cnpj_lookup_status = result.status
    company.cnpj_lookup_message = result.message
    company.tax_regime_checked_at = now_iso()
    changed = False

    if result.source:
        company.tax_regime_source = result.source
    if result.cnae_main:
        company.cnae_main = result.cnae_main
    if result.legal_nature:
        company.legal_nature = result.legal_nature
    if result.company_size:
        company.company_size = result.company_size

    if result.tax_regime and not (company.tax_regime or "").strip():
        company.tax_regime = result.tax_regime
        changed = True
    if result.crt and not (company.crt or "").strip():
        company.crt = result.crt
        changed = True
    return changed

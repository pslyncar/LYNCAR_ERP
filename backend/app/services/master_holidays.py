from __future__ import annotations

import gzip
import json
import unicodedata
from datetime import UTC, date, datetime, timedelta
from urllib.parse import quote
from urllib.request import Request, urlopen

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.master_holiday import MasterHoliday, MasterHolidaySync

SYNC_TTL_DAYS = 30
OPEN_SOURCE_BASE_URL = (
    "https://raw.githubusercontent.com/joaopbini/feriados-brasil/master/dados"
)
STATE_FIXED_HOLIDAYS: dict[str, list[tuple[int, int, str]]] = {
    "SP": [
        (7, 9, "Revolucao Constitucionalista de 1932"),
    ],
}


def ensure_master_holidays_for_scope(
    db: Session,
    *,
    year: int,
    city: str | None = None,
    city_code: str | int | None = None,
    state: str | None = None,
) -> None:
    """Mantem cache central de feriados no banco master.

    Nacional e carregado por ano. Municipal/estadual e carregado por cidade/UF
    quando houver token da FeriadosAPI. Uma consulta bem-sucedida so e repetida
    depois de 30 dias, evitando gasto desnecessario de requisicoes.
    """

    if not get_settings().holiday_sync_enabled:
        return
    normalized_state = state.strip().upper() if state else None
    normalized_city = city.strip() if city else None
    normalized_city_code = _normalize_city_code(city_code)
    if normalized_city_code is None and normalized_city and normalized_state:
        resolved = _resolve_ibge_city_code(normalized_city, normalized_state)
        normalized_city_code = str(resolved) if resolved is not None else None
    _ensure_national_holidays(db, year)
    _ensure_open_source_holidays(db, year)
    if normalized_state:
        _ensure_state_holidays(db, year=year, state=normalized_state)
        _ensure_builtin_state_holidays(db, year=year, state=normalized_state)
    if normalized_city and normalized_state:
        _ensure_city_holidays(
            db,
            year=year,
            city=normalized_city,
            state=normalized_state,
            city_code=normalized_city_code,
        )


def _ensure_builtin_state_holidays(db: Session, *, year: int, state: str) -> None:
    normalized_state = state.strip().upper()
    for month, day, description in STATE_FIXED_HOLIDAYS.get(normalized_state, []):
        _upsert_holiday(
            db,
            holiday_date=date(year, month, day),
            description=description,
            holiday_type="estadual",
            city=None,
            city_code=None,
            state=normalized_state,
            source="builtin_state",
        )
    db.flush()


def is_non_business_day(
    db: Session,
    target_date: date,
    *,
    city: str | None = None,
    city_code: str | int | None = None,
    state: str | None = None,
) -> bool:
    if target_date.weekday() >= 5:
        return True
    ensure_master_holidays_for_scope(
        db,
        year=target_date.year,
        city=city,
        city_code=city_code,
        state=state,
    )
    return _holiday_exists(db, target_date, city=city, city_code=city_code, state=state)


def is_holiday(
    db: Session,
    target_date: date,
    *,
    city: str | None = None,
    city_code: str | int | None = None,
    state: str | None = None,
) -> bool:
    """Consulta apenas feriado na base central do Master.

    Diferente de is_non_business_day, esta funcao nao considera sabado/domingo.
    Ela existe para modulos que possuem regra propria para sabado, domingo e feriado.
    """

    ensure_master_holidays_for_scope(
        db,
        year=target_date.year,
        city=city,
        city_code=city_code,
        state=state,
    )
    return _holiday_exists(db, target_date, city=city, city_code=city_code, state=state)


def next_business_day(
    db: Session,
    target_date: date,
    *,
    city: str | None = None,
    city_code: str | int | None = None,
    state: str | None = None,
) -> date:
    adjusted = target_date
    while is_non_business_day(db, adjusted, city=city, city_code=city_code, state=state):
        adjusted += timedelta(days=1)
    return adjusted


def _ensure_open_source_holidays(db: Session, year: int) -> None:
    if _sync_is_fresh(db, year=year, city=None, city_code=None, state=None, holiday_type="open_source"):
        return
    sync = _touch_sync(
        db,
        year=year,
        city=None,
        city_code=None,
        state=None,
        holiday_type="open_source",
    )
    try:
        location = _fetch_open_source_location()
        _deactivate_source_for_year(db, year=year, source="open_source")
        seen: set[tuple[date, str, str, str | None, str | None]] = set()
        for kind in ("estadual", "municipal"):
            data = _fetch_json(
                f"{OPEN_SOURCE_BASE_URL}/feriados/{kind}/json/{year}.json"
            )
            rows = data if isinstance(data, list) else []
            for item in rows:
                holiday_date = _parse_any_date(item.get("data") or item.get("date"))
                name = item.get("nome") or item.get("name") or item.get("fullName")
                holiday_type = _normalize_holiday_type(item.get("tipo") or item.get("type") or kind)
                if holiday_date is None or not name or holiday_type not in {"estadual", "municipal"}:
                    continue
                state = str(item.get("uf") or "").strip().upper() or None
                city = None
                city_code = None
                if holiday_type == "municipal":
                    city_code = _normalize_city_code(item.get("codigo_ibge"))
                    city_info = location["municipios"].get(city_code or "")
                    if city_info:
                        city = city_info["nome"]
                        state = city_info["uf"]
                    if city is None or city_code is None:
                        continue
                elif state is None:
                    continue
                key = (holiday_date, str(name), holiday_type, city, state)
                if key in seen:
                    continue
                seen.add(key)
                _upsert_holiday(
                    db,
                    holiday_date=holiday_date,
                    description=str(name),
                    holiday_type=holiday_type,
                    city=city,
                    city_code=city_code,
                    state=state,
                    source="open_source",
                )
        _mark_sync_success(sync, source="open_source")
        db.flush()
    except Exception as exc:
        _mark_sync_error(sync, str(exc))
        db.flush()


def _ensure_national_holidays(db: Session, year: int) -> None:
    if _sync_is_fresh(db, year=year, city=None, city_code=None, state=None, holiday_type="nacional"):
        return
    sync = _touch_sync(db, year=year, city=None, city_code=None, state=None, holiday_type="nacional")
    try:
        data = _fetch_json(f"https://brasilapi.com.br/api/feriados/v1/{year}")
        rows = data if isinstance(data, list) else []
        _deactivate_scope(db, year=year, city=None, state=None, holiday_type="nacional")
        for item in rows:
            holiday_date = _parse_iso_date(item.get("date"))
            name = item.get("name") or item.get("fullName")
            if holiday_date is None or not name:
                continue
            _upsert_holiday(
                db,
                holiday_date=holiday_date,
                description=str(name),
                holiday_type="nacional",
                city=None,
                city_code=None,
                state=None,
                source="brasilapi",
            )
        _mark_sync_success(sync, source="brasilapi")
        db.flush()
    except Exception as exc:
        _mark_sync_error(sync, str(exc))
        db.flush()


def _ensure_city_holidays(
    db: Session,
    *,
    year: int,
    city: str,
    state: str,
    city_code: str | int | None = None,
) -> None:
    settings = get_settings()
    if not settings.feriados_api_token:
        return
    normalized_city = city.strip()
    normalized_state = state.strip().upper()
    if not normalized_city or not normalized_state:
        return
    if _sync_is_fresh(
        db,
        year=year,
        city=normalized_city,
        city_code=city_code,
        state=normalized_state,
        holiday_type="municipal",
    ):
        return
    sync = _touch_sync(
        db,
        year=year,
        city=normalized_city,
        city_code=city_code,
        state=normalized_state,
        holiday_type="municipal",
    )
    try:
        ibge_code = int(city_code) if _normalize_city_code(city_code) else _resolve_ibge_city_code(normalized_city, normalized_state)
        if ibge_code is None:
            raise RuntimeError("Codigo IBGE da cidade nao encontrado.")
        headers = {
            "Authorization": f"Bearer {settings.feriados_api_token}",
            "X-API-Key": settings.feriados_api_token,
        }
        data = _fetch_json(
            f"https://feriadosapi.com/api/v1/feriados/cidade/{ibge_code}?ano={year}",
            headers=headers,
        )
        rows = data.get("feriados", []) if isinstance(data, dict) else data
        _deactivate_city_scope(db, year=year, city=normalized_city, state=normalized_state)
        for item in rows if isinstance(rows, list) else []:
            holiday_date = _parse_any_date(item.get("data") or item.get("date"))
            name = item.get("nome") or item.get("name") or item.get("fullName")
            holiday_type = _normalize_holiday_type(item.get("tipo") or item.get("type"))
            if holiday_date is None or not name:
                continue
            _upsert_holiday(
                db,
                holiday_date=holiday_date,
                description=str(name),
                holiday_type=holiday_type,
                city=normalized_city,
                city_code=str(ibge_code),
                state=normalized_state,
                source="feriadosapi",
            )
        _mark_sync_success(sync, source="feriadosapi")
        db.flush()
    except Exception as exc:
        _mark_sync_error(sync, str(exc))
        db.flush()


def _ensure_state_holidays(db: Session, *, year: int, state: str) -> None:
    settings = get_settings()
    if not settings.feriados_api_token:
        return
    normalized_state = state.strip().upper()
    if not normalized_state:
        return
    if _sync_is_fresh(
        db,
        year=year,
        city=None,
        city_code=None,
        state=normalized_state,
        holiday_type="estadual",
    ):
        return
    sync = _touch_sync(
        db,
        year=year,
        city=None,
        city_code=None,
        state=normalized_state,
        holiday_type="estadual",
    )
    try:
        headers = {
            "Authorization": f"Bearer {settings.feriados_api_token}",
            "X-API-Key": settings.feriados_api_token,
        }
        data = _fetch_json(
            f"https://feriadosapi.com/api/v1/feriados/estado/{quote(normalized_state)}?ano={year}",
            headers=headers,
        )
        rows = data.get("feriados", []) if isinstance(data, dict) else data
        _deactivate_scope(
            db,
            year=year,
            city=None,
            state=normalized_state,
            holiday_type="estadual",
        )
        for item in rows if isinstance(rows, list) else []:
            holiday_date = _parse_any_date(item.get("data") or item.get("date"))
            name = item.get("nome") or item.get("name") or item.get("fullName")
            holiday_type = _normalize_holiday_type(item.get("tipo") or item.get("type"))
            if holiday_date is None or not name:
                continue
            if holiday_type == "nacional":
                continue
            target_city = None
            target_state = None
            if holiday_type == "estadual":
                target_state = normalized_state
            elif holiday_type == "municipal":
                target_city = str(item.get("municipio") or item.get("cidade") or "").strip() or None
                target_state = normalized_state
                if target_city is None:
                    continue
            _upsert_holiday(
                db,
                holiday_date=holiday_date,
                description=str(name),
                holiday_type=holiday_type,
                city=target_city,
                city_code=_normalize_city_code(item.get("codigo_ibge")),
                state=target_state,
                source="feriadosapi_estado",
            )
        _mark_sync_success(sync, source="feriadosapi_estado")
        db.flush()
    except Exception as exc:
        _mark_sync_error(sync, str(exc))
        db.flush()


def _sync_is_fresh(
    db: Session,
    *,
    year: int,
    city: str | None,
    city_code: str | int | None,
    state: str | None,
    holiday_type: str,
) -> bool:
    sync = _get_sync(
        db,
        year=year,
        city=city,
        city_code=city_code,
        state=state,
        holiday_type=holiday_type,
    )
    if sync is None or sync.last_success_at is None or sync.status != "success":
        return False
    return sync.last_success_at >= datetime.now(UTC) - timedelta(days=SYNC_TTL_DAYS)


def _get_sync(
    db: Session,
    *,
    year: int,
    city: str | None,
    city_code: str | int | None,
    state: str | None,
    holiday_type: str,
) -> MasterHolidaySync | None:
    query = select(MasterHolidaySync).where(
        MasterHolidaySync.year == year,
        MasterHolidaySync.holiday_type == holiday_type,
    )
    query = query.where(MasterHolidaySync.city.is_(None) if city is None else MasterHolidaySync.city == city)
    query = query.where(MasterHolidaySync.state.is_(None) if state is None else MasterHolidaySync.state == state)
    return db.scalar(query.limit(1))


def _touch_sync(
    db: Session,
    *,
    year: int,
    city: str | None,
    city_code: str | int | None,
    state: str | None,
    holiday_type: str,
) -> MasterHolidaySync:
    normalized_city_code = _normalize_city_code(city_code)
    sync = _get_sync(
        db,
        year=year,
        city=city,
        city_code=normalized_city_code,
        state=state,
        holiday_type=holiday_type,
    )
    if sync is None:
        sync = MasterHolidaySync(
            year=year,
            city=city,
            city_code=normalized_city_code,
            state=state,
            holiday_type=holiday_type,
        )
        db.add(sync)
    sync.status = "running"
    sync.city_code = normalized_city_code
    sync.last_attempt_at = datetime.now(UTC)
    return sync


def _mark_sync_success(sync: MasterHolidaySync, *, source: str) -> None:
    sync.status = "success"
    sync.source = source
    sync.message = None
    sync.last_success_at = datetime.now(UTC)


def _mark_sync_error(sync: MasterHolidaySync, message: str) -> None:
    sync.status = "error"
    sync.message = message[:1000]


def _holiday_exists(
    db: Session,
    target_date: date,
    *,
    city: str | None,
    city_code: str | int | None,
    state: str | None,
) -> bool:
    query = select(MasterHoliday.id).where(
        MasterHoliday.holiday_date == target_date,
        MasterHoliday.active.is_(True),
    )
    scopes = [MasterHoliday.holiday_type == "nacional"]
    if state:
        scopes.append(
            and_(
                MasterHoliday.city.is_(None),
                MasterHoliday.state == state.strip().upper(),
            )
        )
    if city and state:
        scopes.append(
            and_(
                MasterHoliday.city == city.strip(),
                MasterHoliday.state == state.strip().upper(),
            )
        )
    normalized_city_code = _normalize_city_code(city_code)
    if normalized_city_code and state:
        scopes.append(
            and_(
                MasterHoliday.city_code == normalized_city_code,
                MasterHoliday.state == state.strip().upper(),
            )
        )

    return db.scalar(query.where(or_(*scopes)).limit(1)) is not None


def _deactivate_scope(
    db: Session,
    *,
    year: int,
    city: str | None,
    state: str | None,
    holiday_type: str,
) -> None:
    query = select(MasterHoliday).where(
        MasterHoliday.holiday_date >= date(year, 1, 1),
        MasterHoliday.holiday_date <= date(year, 12, 31),
        MasterHoliday.holiday_type == holiday_type,
    )
    query = query.where(MasterHoliday.city.is_(None) if city is None else MasterHoliday.city == city)
    query = query.where(MasterHoliday.state.is_(None) if state is None else MasterHoliday.state == state)
    for holiday in db.scalars(query).all():
        holiday.active = False


def _deactivate_city_scope(db: Session, *, year: int, city: str, state: str) -> None:
    query = select(MasterHoliday).where(
        MasterHoliday.holiday_date >= date(year, 1, 1),
        MasterHoliday.holiday_date <= date(year, 12, 31),
        MasterHoliday.city == city,
        MasterHoliday.state == state,
    )
    for holiday in db.scalars(query).all():
        holiday.active = False


def _deactivate_source_for_year(db: Session, *, year: int, source: str) -> None:
    query = select(MasterHoliday).where(
        MasterHoliday.holiday_date >= date(year, 1, 1),
        MasterHoliday.holiday_date <= date(year, 12, 31),
        MasterHoliday.source == source,
    )
    for holiday in db.scalars(query).all():
        holiday.active = False


def _upsert_holiday(
    db: Session,
    *,
    holiday_date: date,
    description: str,
    holiday_type: str,
    city: str | None,
    city_code: str | int | None,
    state: str | None,
    source: str,
) -> None:
    normalized_city_code = _normalize_city_code(city_code)
    query = select(MasterHoliday).where(
        MasterHoliday.holiday_date == holiday_date,
        MasterHoliday.description == description,
        MasterHoliday.holiday_type == holiday_type,
    )
    query = query.where(MasterHoliday.city.is_(None) if city is None else MasterHoliday.city == city)
    query = query.where(MasterHoliday.state.is_(None) if state is None else MasterHoliday.state == state)
    existing = db.scalar(query.limit(1))
    if existing is None:
        existing = MasterHoliday(
            holiday_date=holiday_date,
            description=description,
            holiday_type=holiday_type,
            city=city,
            city_code=normalized_city_code,
            state=state,
        )
        db.add(existing)
    existing.active = True
    existing.description = description
    existing.city_code = normalized_city_code
    existing.source = source
    existing.synced_at = datetime.now(UTC)


def _resolve_ibge_city_code(city: str, state: str) -> int | None:
    try:
        data = _fetch_json(
            f"https://servicodados.ibge.gov.br/api/v1/localidades/estados/{quote(state)}/municipios"
        )
    except Exception:
        return None
    wanted = _normalize_text(city)
    for item in data if isinstance(data, list) else []:
        if _normalize_text(str(item.get("nome", ""))) == wanted:
            try:
                return int(item["id"])
            except (KeyError, TypeError, ValueError):
                return None
    return None


def _fetch_json(url: str, headers: dict[str, str] | None = None):
    request = Request(
        url,
        headers={
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "User-Agent": "Lyncar/1.0",
            **(headers or {}),
        },
    )
    with urlopen(request, timeout=8) as response:
        body = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
        return json.loads(body.decode("utf-8"))


def _fetch_open_source_location() -> dict[str, dict[str, dict[str, str]]]:
    estados_data = _fetch_json(f"{OPEN_SOURCE_BASE_URL}/localizacao/estados/estados.json")
    municipios_data = _fetch_json(
        f"{OPEN_SOURCE_BASE_URL}/localizacao/municipios/municipios.json"
    )
    estados: dict[str, str] = {}
    for item in estados_data if isinstance(estados_data, list) else []:
        codigo_uf = str(item.get("codigo_uf") or "").strip()
        uf = str(item.get("uf") or "").strip().upper()
        if codigo_uf and uf:
            estados[codigo_uf] = uf
    municipios: dict[str, dict[str, str]] = {}
    for item in municipios_data if isinstance(municipios_data, list) else []:
        city_code = _normalize_city_code(item.get("codigo_ibge"))
        codigo_uf = str(item.get("codigo_uf") or "").strip()
        uf = estados.get(codigo_uf) or str(item.get("uf") or "").strip().upper()
        nome = str(item.get("nome") or "").strip()
        if city_code and uf and nome:
            municipios[city_code] = {"nome": nome, "uf": uf}
    return {"municipios": municipios}


def _normalize_city_code(value: str | int | None) -> str | None:
    text = str(value or "").strip()
    return text if text.isdigit() else None


def _normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value.strip().lower())
    return "".join(char for char in normalized if not unicodedata.combining(char))


def _normalize_holiday_type(value: object) -> str:
    normalized = _normalize_text(str(value or "municipal"))
    if "nacional" in normalized:
        return "nacional"
    if "estadual" in normalized:
        return "estadual"
    if "facultativo" in normalized:
        return "facultativo"
    return "municipal"


def _parse_any_date(value: object) -> date | None:
    text = str(value or "").strip()
    return _parse_iso_date(text) or _parse_br_date(text)


def _parse_iso_date(value: object) -> date | None:
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        return None


def _parse_br_date(value: str) -> date | None:
    parts = value.split("/")
    if len(parts) != 3:
        return None
    try:
        day, month, year = (int(part) for part in parts)
        return date(year, month, day)
    except ValueError:
        return None

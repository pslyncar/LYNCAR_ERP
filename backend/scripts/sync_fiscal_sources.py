"""Sincroniza bases oficiais usadas pelo Assistente Fiscal Inteligente.

Uso manual no servidor:

    python scripts/sync_fiscal_sources.py --strict --retry-until-success

Horario sugerido para agendamento diario:

    03:15 da manha, horario local do servidor.

Se a primeira tentativa falhar porque Siscomex/CONFAZ/internet esta fora,
o modo --retry-until-success tenta novamente de hora em hora ate conseguir
ou ate completar 23h, quando a proxima tarefa diaria assume.

Variaveis opcionais:

    FISCAL_NCM_JSON_URL=https://...
    FISCAL_CFOP_URL=https://...
    FISCAL_CEST_URL=https://...
    FISCAL_IBS_CBS_CLASS_TRIB_URL=https://...
    FISCAL_SYNC_LOG_FILE=/var/log/lyncar/fiscal_sources_sync.log

Se as variaveis nao forem definidas, o script usa fontes oficiais padrao:

    NCM: Portal Unico Siscomex/Classif JSON publico
    CFOP: CONFAZ - tabela CFOP vigente
    CEST: CONFAZ - Convenio ICMS 142/18
    IBS/CBS: Portal DF-e - Classificacao Tributaria da Reforma Tributaria

Observacao: este script alimenta apenas tabelas auxiliares de sugestao/validacao.
Ele nao altera motor fiscal, XML de emissao, assinatura ou transmissao SEFAZ.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import tempfile
from datetime import datetime
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app.main  # noqa: F401,E402  # registra modelos e rotas SQLAlchemy antes da sincronizacao
from app.core.master_database import MasterSessionLocal
from app.services.fiscal_assistant import sync_reference_from_url


DEFAULT_SOURCE_URLS = {
    "ncm": "https://portalunico.siscomex.gov.br/classif/api/publico/nomenclatura/download/json",
    "cfop": "https://www.confaz.fazenda.gov.br/legislacao/ajustes/sinief/copy_of_cfop_cvsn_70_nova",
    "cest": "https://www.confaz.fazenda.gov.br/legislacao/convenios/2018/CV142_18",
    "ibs_cbs_class_trib": "https://dfe-portal.svrs.rs.gov.br/Cff/ClassificacaoTributaria",
}

SOURCE_ENV_NAMES = {
    "ncm": ("FISCAL_NCM_JSON_URL", "FISCAL_NCM_URL"),
    "cfop": ("FISCAL_CFOP_URL", "FISCAL_CFOP_CSV_URL"),
    "cest": ("FISCAL_CEST_URL", "FISCAL_CEST_CSV_URL"),
    "ibs_cbs_class_trib": (
        "FISCAL_IBS_CBS_CLASS_TRIB_URL",
        "FISCAL_CCLASS_TRIB_URL",
    ),
}


def _source_url(source_type: str) -> str:
    for env_name in SOURCE_ENV_NAMES[source_type]:
        value = os.getenv(env_name)
        if value:
            return value
    return DEFAULT_SOURCE_URLS[source_type]


def _write_log(line: str) -> None:
    log_file = os.getenv("FISCAL_SYNC_LOG_FILE")
    if not log_file:
        return
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    with open(log_file, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def _print_and_log(message: str) -> None:
    timestamp = datetime.now().isoformat(timespec="seconds")
    line = f"{timestamp} {message}"
    print(line)
    _write_log(line)


def _lock_path() -> str:
    return os.getenv(
        "FISCAL_SYNC_LOCK_FILE",
        os.path.join(tempfile.gettempdir(), "lyncar_fiscal_sources_sync.lock"),
    )


def _acquire_lock() -> str | None:
    path = _lock_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return None
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(f"pid={os.getpid()} started_at={datetime.now().isoformat(timespec='seconds')}\n")
    return path


def _release_lock(path: str | None) -> None:
    if not path:
        return
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def _run_once(selected_sources: list[str], *, strict: bool) -> bool:
    failed = False
    with MasterSessionLocal() as db:
        for source_type in selected_sources:
            source_url = _source_url(source_type)
            try:
                loaded = sync_reference_from_url(db, source_type, source_url)
                db.commit()
                _print_and_log(f"{source_type}: {loaded} registros sincronizados de {source_url}.")
                if loaded <= 0:
                    failed = True
            except Exception as exc:  # noqa: BLE001
                db.rollback()
                failed = True
                _print_and_log(f"{source_type}: erro ao sincronizar {source_url}: {exc}")
    return not failed or not strict


def main() -> int:
    parser = argparse.ArgumentParser(description="Sincroniza bases fiscais oficiais do Assistente Fiscal.")
    parser.add_argument(
        "--source",
        choices=["ncm", "cfop", "cest", "ibs_cbs_class_trib", "cclass_trib", "cclasstrib"],
        action="append",
        help="Sincroniza somente a fonte informada. Pode repetir.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Retorna erro se alguma fonte falhar ou carregar 0 registros.",
    )
    parser.add_argument(
        "--retry-until-success",
        action="store_true",
        help="Se falhar, tenta novamente ate conseguir. Use --max-retry-hours para limitar.",
    )
    parser.add_argument(
        "--retry-interval-minutes",
        type=int,
        default=60,
        help="Intervalo entre tentativas quando --retry-until-success estiver ativo.",
    )
    parser.add_argument(
        "--max-retry-hours",
        type=int,
        default=0,
        help="Limite opcional de horas tentando novamente. 0 significa sem limite.",
    )
    args = parser.parse_args()
    lock_file = _acquire_lock()
    if lock_file is None:
        _print_and_log("sincronizacao ignorada: ja existe outra rotina fiscal em execucao.")
        return 0
    try:
        selected_sources = args.source or ["ncm", "cfop", "cest", "ibs_cbs_class_trib"]
        deadline = (
            datetime.now() + timedelta(hours=args.max_retry_hours)
            if args.max_retry_hours > 0
            else None
        )
        attempt = 1
        while True:
            _print_and_log(f"inicio tentativa {attempt}: fontes={','.join(selected_sources)}")
            success = _run_once(selected_sources, strict=args.strict)
            if success:
                _print_and_log(f"fim tentativa {attempt}: sincronizacao concluida.")
                return 0
            if not args.retry_until_success or (deadline is not None and datetime.now() >= deadline):
                _print_and_log(f"fim tentativa {attempt}: sincronizacao falhou.")
                return 1
            wait_minutes = max(args.retry_interval_minutes, 1)
            _print_and_log(
                f"tentativa {attempt} falhou; nova tentativa em {wait_minutes} minuto(s)."
            )
            time.sleep(wait_minutes * 60)
            attempt += 1
    finally:
        _release_lock(lock_file)


if __name__ == "__main__":
    raise SystemExit(main())

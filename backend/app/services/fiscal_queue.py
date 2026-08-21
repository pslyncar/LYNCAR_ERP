from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import or_, select, update
from sqlalchemy.orm import Session, selectinload

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.fiscal import (
    CompanyFiscalSetting,
    FiscalDocument,
    FiscalTransmissionJob,
)
from app.models.user import User
from app.services.fiscal_xml import build_processed_nfe_xml
from app.services.nfe_protocol_sp import query_nfe_protocol
from app.services.tenancy import session_for_company

logger = logging.getLogger(__name__)

ACTIVE_JOB_STATUSES = ("pending", "retry", "processing")
TERMINAL_DOCUMENT_STATUSES = (
    "authorized",
    "cancelled",
    "contingency_offline",
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class RetryFiscalJob(Exception):
    def __init__(self, message: str, *, delay_seconds: int = 30) -> None:
        super().__init__(message)
        self.delay_seconds = delay_seconds


def fiscal_lane_key(document: FiscalDocument) -> str:
    return (
        f"{document.environment}:{document.document_type}:"
        f"{int(document.series or 0)}"
    )


def enqueue_fiscal_job(
    db: Session,
    document: FiscalDocument,
    *,
    requested_by_user_id: int | None,
    job_type: str = "authorize",
    delay_seconds: int = 0,
) -> FiscalTransmissionJob:
    job = db.scalar(
        select(FiscalTransmissionJob).where(
            FiscalTransmissionJob.document_id == document.id,
            FiscalTransmissionJob.job_type == job_type,
        )
    )
    next_attempt_at = _utcnow() + timedelta(seconds=delay_seconds)
    if job is None:
        job = FiscalTransmissionJob(
            document_id=document.id,
            requested_by_user_id=requested_by_user_id,
            job_type=job_type,
            lane_key=fiscal_lane_key(document),
            status="pending",
            next_attempt_at=next_attempt_at,
        )
        db.add(job)
    elif job.status not in {"processing", "completed"}:
        job.requested_by_user_id = requested_by_user_id or job.requested_by_user_id
        job.lane_key = fiscal_lane_key(document)
        job.status = "pending"
        job.next_attempt_at = next_attempt_at
        job.last_error = None
    db.flush()
    return job


def resume_fiscal_configuration_jobs(db: Session) -> int:
    """Reavalia notas paradas depois que produto ou regra fiscal foi corrigido."""

    documents = list(
        db.scalars(
            select(FiscalDocument).where(
                FiscalDocument.status == "pending_configuration"
            )
        ).all()
    )
    resumed = 0
    for document in documents:
        document.status = "draft"
        document.sefaz_status_code = None
        document.sefaz_message = None
        enqueue_fiscal_job(
            db,
            document,
            requested_by_user_id=None,
            job_type="authorize",
        )
        resumed += 1
    return resumed


def _retry_delay(attempts: int) -> int:
    schedule = (5, 15, 30, 60, 120, 300, 600, 900)
    return schedule[min(max(attempts - 1, 0), len(schedule) - 1)]


def _load_job(db: Session, job_id: int) -> FiscalTransmissionJob | None:
    return db.scalar(
        select(FiscalTransmissionJob)
        .options(
            selectinload(FiscalTransmissionJob.document),
            selectinload(FiscalTransmissionJob.result_document),
        )
        .where(FiscalTransmissionJob.id == job_id)
    )


def _claim_job(db: Session) -> int | None:
    for document in db.scalars(
        select(FiscalDocument).where(
            FiscalDocument.status.in_(("pending_return", "contingency_offline"))
        )
    ).all():
        job_type = (
            "recover_pending_return"
            if document.status == "pending_return"
            else "transmit_contingency"
        )
        existing = db.scalar(
            select(FiscalTransmissionJob.id).where(
                FiscalTransmissionJob.document_id == document.id,
                FiscalTransmissionJob.job_type == job_type,
            )
        )
        if existing is None:
            enqueue_fiscal_job(
                db,
                document,
                requested_by_user_id=None,
                job_type=job_type,
            )
    stale_before = _utcnow() - timedelta(minutes=15)
    db.execute(
        update(FiscalTransmissionJob)
        .where(
            FiscalTransmissionJob.status == "processing",
            FiscalTransmissionJob.locked_at < stale_before,
        )
        .values(status="retry", locked_at=None, next_attempt_at=_utcnow())
    )
    now = _utcnow()
    job = db.scalar(
        select(FiscalTransmissionJob)
        .where(
            FiscalTransmissionJob.status.in_(("pending", "retry")),
            or_(
                FiscalTransmissionJob.next_attempt_at.is_(None),
                FiscalTransmissionJob.next_attempt_at <= now,
            ),
        )
        .order_by(FiscalTransmissionJob.created_at, FiscalTransmissionJob.id)
        .with_for_update(skip_locked=True)
        .limit(1)
    )
    if job is None:
        db.commit()
        return None
    job.status = "processing"
    job.attempts = int(job.attempts or 0) + 1
    job.locked_at = now
    job.last_error = None
    db.commit()
    return job.id


def _worker_user(db: Session, job: FiscalTransmissionJob) -> User:
    user = db.get(User, job.requested_by_user_id) if job.requested_by_user_id else None
    if user is None:
        user = db.scalar(
            select(User)
            .where(User.active.is_(True))
            .order_by(User.id)
            .limit(1)
        )
    if user is None:
        raise RuntimeError("Empresa sem usuario ativo para registrar a emissao fiscal.")
    return user


def _mark_completed(
    db: Session,
    job_id: int,
    *,
    result_document_id: int | None = None,
) -> None:
    job = db.get(FiscalTransmissionJob, job_id)
    if job is None:
        return
    job.status = "completed"
    job.result_document_id = result_document_id or job.document_id
    job.completed_at = _utcnow()
    job.locked_at = None
    job.next_attempt_at = None
    job.last_error = None
    db.commit()


def _mark_blocked(db: Session, job_id: int, message: str) -> None:
    job = db.get(FiscalTransmissionJob, job_id)
    if job is None:
        return
    job.status = "blocked"
    job.locked_at = None
    job.next_attempt_at = None
    job.last_error = message[:2000]
    db.commit()


def _mark_retry(db: Session, job_id: int, message: str, delay_seconds: int | None = None) -> None:
    job = db.get(FiscalTransmissionJob, job_id)
    if job is None:
        return
    delay = delay_seconds if delay_seconds is not None else _retry_delay(job.attempts)
    job.status = "retry"
    job.locked_at = None
    job.next_attempt_at = _utcnow() + timedelta(seconds=delay)
    job.last_error = message[:2000]
    db.commit()


def _recover_pending_return(db: Session, job: FiscalTransmissionJob) -> FiscalDocument:
    document = db.scalar(
        select(FiscalDocument)
        .where(FiscalDocument.id == job.document_id)
        .with_for_update()
    )
    if document is None:
        raise RuntimeError("Documento pendente de retorno nao encontrado.")
    if document.status == "authorized":
        return document
    if document.status == "not_found_after_timeout":
        return document
    if not document.access_key or not document.xml_signed:
        raise RuntimeError("Documento pendente sem chave ou XML assinado.")
    setting = db.scalar(
        select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id).with_for_update()
    )
    if setting is None:
        raise RuntimeError("Configuracao fiscal nao encontrada.")
    protocol = query_nfe_protocol(setting, document.access_key)
    if protocol.authorized:
        document.status = "authorized"
        document.sefaz_status_code = protocol.status_code
        document.sefaz_message = protocol.message
        document.sefaz_protocol = protocol.protocol
        document.xml_authorized = build_processed_nfe_xml(
            document.xml_signed,
            protocol.response_xml,
        )
        document.authorized_at = _utcnow()
        setting.nfce_last_authorized_number = max(
            int(setting.nfce_last_authorized_number or 0),
            int(document.number or 0),
        )
        contingency = db.scalar(
            select(FiscalDocument).where(
                FiscalDocument.origin_document_id == document.id,
                FiscalDocument.status == "contingency_offline",
            )
        )
        if contingency is not None:
            contingency.status = "duplicate_authorization_review"
            contingency.sefaz_status_code = "ORIGINAL_AUTHORIZED"
            contingency.sefaz_message = (
                "A NFC-e normal foi autorizada apos o timeout. A contingencia nao "
                "foi transmitida e exige revisao/cancelamento pelo responsavel fiscal."
            )
            contingency_job = db.scalar(
                select(FiscalTransmissionJob).where(
                    FiscalTransmissionJob.document_id == contingency.id,
                    FiscalTransmissionJob.job_type == "transmit_contingency",
                )
            )
            if contingency_job is not None:
                contingency_job.status = "blocked"
                contingency_job.next_attempt_at = None
                contingency_job.last_error = contingency.sefaz_message
        db.commit()
        return document
    if protocol.status_code == "217" and int(job.attempts or 0) < 2:
        raise RetryFiscalJob(
            "A chave ainda nao consta na SEFAZ; confirmando novamente antes de liberar a contingencia.",
            delay_seconds=15,
        )
    if protocol.status_code == "217":
        document.status = "not_found_after_timeout"
        document.sefaz_status_code = protocol.status_code
        document.sefaz_message = protocol.message
        db.commit()
        return document
    if protocol.status_code == "656":
        raise RetryFiscalJob(protocol.message, delay_seconds=3600)
    raise RetryFiscalJob(
        f"Consulta da chave retornou {protocol.status_code or '-'}: {protocol.message}",
        delay_seconds=30,
    )


def _process_job(db: Session, job_id: int) -> tuple[str, int | None, str | None]:
    job = _load_job(db, job_id)
    if job is None or job.document is None:
        return "blocked", None, "Trabalho ou documento fiscal nao encontrado."
    user = _worker_user(db, job)
    if job.job_type == "recover_pending_return":
        document = _recover_pending_return(db, job)
        return "completed", document.id, None
    if job.job_type == "transmit_contingency":
        origin = (
            db.get(FiscalDocument, job.document.origin_document_id)
            if job.document.origin_document_id
            else None
        )
        if origin is not None and origin.status == "pending_return":
            raise RetryFiscalJob(
                "Aguardando consulta da NFC-e normal que ficou sem retorno.",
                delay_seconds=15,
            )
        if origin is not None and origin.status == "authorized":
            return (
                "blocked",
                job.document.id,
                "NFC-e normal autorizada; contingencia exige revisao antes de transmitir.",
            )
        from app.api.routes.fiscal import transmit_contingency_fiscal_document

        document = transmit_contingency_fiscal_document(job.document.id, db, user)
    else:
        from app.api.routes.fiscal import authorize_fiscal_document

        document = authorize_fiscal_document(job.document.id, db, user)
    if document.status in TERMINAL_DOCUMENT_STATUSES:
        return "completed", document.id, None
    if document.status in {"rejected", "duplicate_authorization_review"}:
        return "blocked", document.id, document.sefaz_message or "Documento rejeitado."
    if document.status == "pending_configuration":
        return (
            "blocked",
            document.id,
            document.sefaz_message or "Documento aguardando configuração fiscal.",
        )
    raise RetryFiscalJob(
        document.sefaz_message or f"Documento em estado {document.status}.",
    )


def process_one_company_job(company_code: str) -> bool:
    with session_for_company(company_code) as db:
        job_id = _claim_job(db)
    if job_id is None:
        return False
    try:
        with session_for_company(company_code) as db:
            outcome, result_document_id, message = _process_job(db, job_id)
        with session_for_company(company_code) as db:
            if outcome == "completed":
                _mark_completed(db, job_id, result_document_id=result_document_id)
            else:
                _mark_blocked(db, job_id, message or "Processamento fiscal bloqueado.")
    except RetryFiscalJob as exc:
        with session_for_company(company_code) as db:
            _mark_retry(db, job_id, str(exc), exc.delay_seconds)
    except HTTPException as exc:
        detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
        with session_for_company(company_code) as db:
            if exc.status_code == 409:
                _mark_retry(db, job_id, detail, 15)
            else:
                _mark_blocked(db, job_id, detail)
    except Exception as exc:
        logger.exception(
            "Falha inesperada no trabalho fiscal %s da empresa %s",
            job_id,
            company_code,
        )
        with session_for_company(company_code) as db:
            _mark_retry(db, job_id, f"{type(exc).__name__}: {exc}")
    return True


class FiscalQueueWorker:
    def __init__(self) -> None:
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="fiscal-queue-worker",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)

    def _run(self) -> None:
        while not self._stop.is_set():
            worked = False
            try:
                with MasterSessionLocal() as master_db:
                    codes = list(
                        master_db.scalars(
                            select(Company.code).where(
                                Company.active.is_(True),
                                Company.status == "active",
                            )
                        ).all()
                    )
                for code in codes:
                    if self._stop.is_set():
                        return
                    worked = process_one_company_job(code) or worked
            except Exception:
                logger.exception("Falha no ciclo do worker fiscal")
                worked = False
            self._stop.wait(0.25 if worked else 2.0)


fiscal_queue_worker = FiscalQueueWorker()

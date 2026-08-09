from datetime import UTC, datetime
import hashlib

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select

from app.api.dependencies import bearer_scheme, require_master_permission
from app.core.config import get_settings
from app.core.master_database import MasterSessionLocal
from app.core.security import decode_access_token
from app.models.company import Company
from app.models.pdv_update import (
    PdvAppVersion,
    PdvAppVersionRollout,
    PdvTerminalUpdateLog,
)
from app.schemas.pdv_update import (
    PdvAppVersionCreate,
    PdvAppVersionRead,
    PdvAppVersionRolloutCreate,
    PdvAppVersionRolloutRead,
    PdvUpdateCheckResponse,
)
from app.services.tenancy import normalize_company_code

router = APIRouter()


def _version_key(value: str | None) -> tuple[int, ...]:
    parts: list[int] = []
    for part in (value or "").replace("-", ".").split("."):
        digits = "".join(char for char in part if char.isdigit())
        if digits:
            parts.append(int(digits))
    return tuple(parts or [0])


def _is_newer(target: PdvAppVersion, current_version: str) -> bool:
    if target.build_number:
        current_key = _version_key(current_version)
        target_key = _version_key(target.version)
        if target_key != current_key:
            return target_key > current_key
    return _version_key(target.version) > _version_key(current_version)


def _supports_current_version(target: PdvAppVersion, current_version: str) -> bool:
    if not target.min_supported_version:
        return True
    return _version_key(current_version) >= _version_key(target.min_supported_version)


def _rollout_bucket(company_code: str, terminal_id: str | None) -> int:
    base = f"{company_code}|{terminal_id or ''}".encode("utf-8")
    return int(hashlib.sha256(base).hexdigest()[:8], 16) % 100


def _rollout_matches(
    rollout: PdvAppVersionRollout,
    *,
    company: Company | None,
    company_code: str,
    plan_code: str,
    terminal_id: str | None,
    channel: str,
) -> bool:
    if not rollout.enabled:
        return False
    if rollout.channel != channel:
        return False
    if rollout.company_id is not None:
        if company is None or company.id != rollout.company_id:
            return False
    if rollout.company_code and normalize_company_code(rollout.company_code) != company_code:
        return False
    if rollout.plan and rollout.plan.strip().lower() != plan_code:
        return False
    if rollout.percent is not None and rollout.percent < 100:
        if _rollout_bucket(company_code, terminal_id) >= rollout.percent:
            return False
    return True


def _candidate_versions(
    *,
    company: Company | None,
    company_code: str,
    plan_code: str,
    platform: str,
    channel: str,
    terminal_id: str | None,
) -> list[tuple[PdvAppVersion, bool]]:
    with MasterSessionLocal() as db:
        versions = list(
            db.scalars(
                select(PdvAppVersion)
                .where(
                    PdvAppVersion.active.is_(True),
                    PdvAppVersion.platform == platform,
                    PdvAppVersion.channel == channel,
                )
                .order_by(PdvAppVersion.build_number.desc(), PdvAppVersion.id.desc())
            ).all()
        )
        result: list[tuple[PdvAppVersion, bool]] = []
        for version in versions:
            rollouts = list(
                db.scalars(
                    select(PdvAppVersionRollout).where(
                        PdvAppVersionRollout.version_id == version.id,
                        PdvAppVersionRollout.enabled.is_(True),
                    )
                ).all()
            )
            if not rollouts:
                result.append((version, bool(version.required)))
                continue
            matched = [
                rollout
                for rollout in rollouts
                if _rollout_matches(
                    rollout,
                    company=company,
                    company_code=company_code,
                    plan_code=plan_code,
                    terminal_id=terminal_id,
                    channel=channel,
                )
            ]
            if matched:
                result.append((version, any(item.mandatory for item in matched) or version.required))
        return result


def _log_update_available(
    *,
    company: Company | None,
    company_code: str,
    terminal_id: str | None,
    current_version: str,
    target_version: str,
) -> None:
    with MasterSessionLocal() as db:
        log = db.scalar(
            select(PdvTerminalUpdateLog).where(
                PdvTerminalUpdateLog.company_code == company_code,
                PdvTerminalUpdateLog.terminal_id == terminal_id,
                PdvTerminalUpdateLog.target_version == target_version,
                PdvTerminalUpdateLog.status == "available",
            )
        )
        if log is None:
            log = PdvTerminalUpdateLog(
                company_id=company.id if company else None,
                company_code=company_code,
                terminal_id=terminal_id,
                current_version=current_version,
                target_version=target_version,
                status="available",
            )
            db.add(log)
        else:
            log.current_version = current_version
            log.checked_at = datetime.now(UTC)
        db.commit()


@router.get("/pdv/update/check", response_model=PdvUpdateCheckResponse)
def check_pdv_update(
    current_version: str = Query(default="0.0.0", max_length=40),
    platform: str = Query(default="windows", max_length=30),
    channel: str = Query(default="stable", max_length=30),
    terminal_id: str | None = Query(default=None, max_length=180),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> PdvUpdateCheckResponse:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de acesso ausente.",
        )
    try:
        payload = decode_access_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        ) from exc

    settings = get_settings()
    company_code = normalize_company_code(str(payload.get("company_code") or ""))
    if not company_code or company_code == settings.master_company_code:
        return PdvUpdateCheckResponse(
            update_available=False,
            message="Atualizacao nao aplicavel para master.",
        )

    platform = platform.strip().lower() or "windows"
    channel = channel.strip().lower() or "stable"
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == company_code))
        if company is None or not company.active or company.status != "active":
            return PdvUpdateCheckResponse(
                update_available=False,
                message="Empresa inativa ou nao encontrada.",
            )
        plan_code = (company.plan or "start").strip().lower()

    candidates = _candidate_versions(
        company=company,
        company_code=company_code,
        plan_code=plan_code,
        platform=platform,
        channel=channel,
        terminal_id=terminal_id,
    )
    for version, mandatory in candidates:
        if not _supports_current_version(version, current_version):
            continue
        if not _is_newer(version, current_version):
            continue
        _log_update_available(
            company=company,
            company_code=company_code,
            terminal_id=terminal_id,
            current_version=current_version,
            target_version=version.version,
        )
        return PdvUpdateCheckResponse(
            update_available=True,
            version=version.version,
            build_number=version.build_number,
            required=bool(version.required),
            mandatory=mandatory,
            url=version.file_url,
            sha256=version.file_sha256,
            size=version.file_size,
            release_notes=version.release_notes,
            install_when="cashier_closed",
            message=f"Nova versao do PDV disponivel: {version.version}.",
        )
    return PdvUpdateCheckResponse(
        update_available=False,
        message="PDV atualizado.",
    )


@router.get("/pdv/versions", response_model=list[PdvAppVersionRead])
def list_pdv_versions(_: dict = Depends(require_master_permission("master:pdv_terminals"))) -> list[PdvAppVersion]:
    with MasterSessionLocal() as db:
        return list(
            db.scalars(
                select(PdvAppVersion).order_by(
                    PdvAppVersion.platform,
                    PdvAppVersion.channel,
                    PdvAppVersion.build_number.desc(),
                    PdvAppVersion.id.desc(),
                )
            ).all()
        )


@router.post("/pdv/versions", response_model=PdvAppVersionRead)
def create_pdv_version(
    payload: PdvAppVersionCreate,
    master_payload: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvAppVersion:
    with MasterSessionLocal() as db:
        version = PdvAppVersion(
            **payload.model_dump(),
            platform=payload.platform.strip().lower() or "windows",
            channel=payload.channel.strip().lower() or "stable",
            file_sha256=payload.file_sha256.strip().upper(),
            created_by=str(master_payload.get("sub") or "master"),
        )
        db.add(version)
        db.commit()
        db.refresh(version)
        return version


@router.post("/pdv/rollouts", response_model=PdvAppVersionRolloutRead)
def create_pdv_rollout(
    payload: PdvAppVersionRolloutCreate,
    _: dict = Depends(require_master_permission("master:pdv_terminals")),
) -> PdvAppVersionRollout:
    with MasterSessionLocal() as db:
        version = db.get(PdvAppVersion, payload.version_id)
        if version is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Versao do PDV nao encontrada.",
            )
        rollout = PdvAppVersionRollout(
            **payload.model_dump(),
            company_code=normalize_company_code(payload.company_code)
            if payload.company_code
            else None,
            plan=payload.plan.strip().lower() if payload.plan else None,
            channel=payload.channel.strip().lower() or version.channel,
        )
        db.add(rollout)
        db.commit()
        db.refresh(rollout)
        return rollout


@router.get("/pdv/rollouts", response_model=list[PdvAppVersionRolloutRead])
def list_pdv_rollouts(_: dict = Depends(require_master_permission("master:pdv_terminals"))) -> list[PdvAppVersionRollout]:
    with MasterSessionLocal() as db:
        return list(
            db.scalars(
                select(PdvAppVersionRollout).order_by(
                    PdvAppVersionRollout.id.desc()
                )
            ).all()
        )

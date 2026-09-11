from datetime import UTC, datetime
import secrets

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.pdv_terminal import PdvTerminal
from app.models.user import User
from app.services.company_modules import resolve_effective_modules
from app.services.plan_limits import effective_plan_limits_for, normalize_plan_code
from app.services.tenancy import session_for_company


def _modules_for(company: Company, plan: str, business_type: str | None) -> list[str]:
    return resolve_effective_modules(
        business_type or company.business_type,
        plan,
        company.manual_module_grants,
        company.manual_module_revocations,
    )


def _tenant_resources(company: Company) -> tuple[list[User], list[PdvTerminal]]:
    try:
        with session_for_company(company.code) as db:
            users = list(
                db.scalars(
                    select(User)
                    .where(User.active.is_(True))
                    .where(~User.email.endswith("_pdv_terminal@lyncar.local"))
                    .order_by(User.name.asc(), User.id.asc())
                ).all()
            )
            terminals = list(
                db.scalars(
                    select(PdvTerminal)
                    .where(PdvTerminal.active.is_(True))
                    .where(PdvTerminal.activation_status != "revoked")
                    .order_by(PdvTerminal.cash_register_number.asc(), PdvTerminal.id.asc())
                ).all()
            )
            return users, terminals
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Não foi possível acessar os dados da empresa: {exc}",
        ) from exc


def _terminal_item(terminal: PdvTerminal) -> dict:
    label = f"Caixa {terminal.cash_register_number}"
    detail = terminal.device_label or terminal.machine_name or "Terminal PDV Windows"
    return {"id": terminal.id, "label": label, "detail": detail, "active": terminal.active}


def preview_plan_change(company_id: int, target_plan: str, target_business_type: str | None):
    with MasterSessionLocal() as master:
        company = master.get(Company, company_id)
        if company is None:
            raise HTTPException(status_code=404, detail="Empresa não encontrada.")

        current_plan = normalize_plan_code(company.plan)
        target_plan = normalize_plan_code(target_plan)
        target_type = target_business_type or company.business_type
        limits = effective_plan_limits_for(company, target_plan, target_type)
        current_modules = _modules_for(company, current_plan, company.business_type)
        target_modules = _modules_for(company, target_plan, target_type)
        users, terminals = _tenant_resources(company)
        max_users = limits["max_users"]
        max_terminals = limits["max_pdv_terminals"]
        excess_users = max(0, len(users) - max_users) if max_users is not None else 0
        pdv_windows_removed = "pdv_windows" not in target_modules
        excess_terminals = (
            len(terminals)
            if pdv_windows_removed
            else max(0, len(terminals) - max_terminals)
            if max_terminals is not None
            else 0
        )
        return {
            "company_id": company.id,
            "company_code": company.code,
            "current_plan": current_plan,
            "target_plan": target_plan,
            "current_modules": current_modules,
            "target_modules": target_modules,
            "removed_modules": sorted(set(current_modules) - set(target_modules)),
            "users": [
                {"id": user.id, "label": user.name, "detail": user.email, "active": user.active}
                for user in users
            ],
            "terminals": [_terminal_item(terminal) for terminal in terminals],
            "max_users": max_users,
            "max_pdv_terminals": max_terminals,
            "active_users": len(users),
            "active_terminals": len(terminals),
            "required_user_selections": excess_users,
            "required_terminal_selections": excess_terminals,
            "pdv_windows_will_be_revoked": pdv_windows_removed and bool(terminals),
        }


def apply_plan_change(
    company_id: int,
    target_plan: str,
    target_business_type: str | None,
    user_ids: list[int],
    terminal_ids: list[int],
):
    preview = preview_plan_change(company_id, target_plan, target_business_type)
    selected_users = set(user_ids)
    selected_terminals = set(terminal_ids)
    available_users = {item["id"] for item in preview["users"]}
    available_terminals = {item["id"] for item in preview["terminals"]}
    if not selected_users <= available_users or not selected_terminals <= available_terminals:
        raise HTTPException(status_code=409, detail="A seleção contém recursos inválidos.")
    if len(selected_users) < preview["required_user_selections"]:
        raise HTTPException(status_code=409, detail="Selecione os usuários que serão inativados.")
    if len(selected_terminals) < preview["required_terminal_selections"]:
        raise HTTPException(status_code=409, detail="Selecione os terminais PDV que serão revogados.")
    if preview["pdv_windows_will_be_revoked"] and selected_terminals != available_terminals:
        raise HTTPException(status_code=409, detail="Todos os terminais PDV Windows precisam ser revogados neste plano.")

    target_modules = preview["target_modules"]
    with MasterSessionLocal() as master:
        company = master.get(Company, company_id)
        if company is None:
            raise HTTPException(status_code=404, detail="Empresa não encontrada.")
        with session_for_company(company.code) as tenant:
            now = datetime.now(UTC)
            if selected_users:
                for user in tenant.scalars(select(User).where(User.id.in_(selected_users))).all():
                    user.active = False
            for terminal in tenant.scalars(select(PdvTerminal).where(PdvTerminal.id.in_(selected_terminals))).all():
                terminal.active = False
                terminal.activation_status = "revoked"
                terminal.current_status = "revoked"
                terminal.activation_code_hash = None
                terminal.activation_code_expires_at = None
                terminal.activated_at = None
                terminal.terminal_key = f"revoked:{secrets.token_urlsafe(32)}"
                terminal.updated_at = now
            tenant.commit()

        company.plan = preview["target_plan"]
        if target_business_type:
            company.business_type = target_business_type
        company.enabled_modules = target_modules
        master.commit()
    return {
        "company_id": company_id,
        "target_plan": preview["target_plan"],
        "inactivated_user_ids": sorted(selected_users),
        "revoked_terminal_ids": sorted(selected_terminals),
        "target_modules": target_modules,
    }

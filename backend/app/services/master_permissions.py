from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.master_permission import MasterUserPermission
from app.models.master_user import MasterUser

MASTER_PERMISSION_DEFINITIONS = [
    {
        "code": "master:manage",
        "label": "Acesso total",
        "module": "master",
        "description": "Permite acessar e alterar todas as áreas do painel master.",
    },
    {
        "code": "master:companies",
        "label": "Empresas",
        "module": "clientes",
        "description": "Permite cadastrar e alterar empresas/clientes.",
    },
    {
        "code": "master:billing",
        "label": "Financeiro master",
        "module": "financeiro",
        "description": "Permite ver e administrar cobranças, planos e pagamentos.",
    },
    {
        "code": "master:pdv_terminals",
        "label": "Terminais PDV",
        "module": "pdv",
        "description": "Permite gerar códigos, editar caixas e excluir terminais PDV.",
    },
    {
        "code": "master:support",
        "label": "Suporte",
        "module": "suporte",
        "description": "Permite atender chamados de suporte dos clientes.",
    },
    {
        "code": "master:staff",
        "label": "Funcionários master",
        "module": "equipe",
        "description": "Permite criar acessos de funcionários e definir permissões.",
    },
    {
        "code": "master:content",
        "label": "Conteúdos e avisos",
        "module": "conteudo",
        "description": "Permite administrar avisos, certificados e loja.",
    },
]


def master_permission_codes() -> set[str]:
    return {item["code"] for item in MASTER_PERMISSION_DEFINITIONS}


def is_owner_master_user(user: MasterUser) -> bool:
    settings = get_settings()
    return user.email.lower() == settings.master_admin_email.lower()


def get_master_user_permission_codes(db: Session, user: MasterUser) -> list[str]:
    if is_owner_master_user(user):
        return sorted(master_permission_codes())
    rows = db.scalars(
        select(MasterUserPermission.permission_code).where(
            MasterUserPermission.user_id == user.id
        )
    ).all()
    codes = set(rows)
    return sorted(code for code in codes if code in master_permission_codes())


def master_user_has_permission(db: Session, user: MasterUser, permission_code: str) -> bool:
    permissions = set(get_master_user_permission_codes(db, user))
    return "master:manage" in permissions or permission_code in permissions

"""Read-only, tenant-scoped data tools used by Lyna.

The model never receives a database session and never builds SQL.  This module
is the small gateway between the authenticated ERP request and the language
model: every query uses the already tenant-bound session from ``get_db``,
checks the user's permission, limits the result, and returns a safe summary.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.models.client import Client
from app.models.fiscal import FiscalDocument
from app.models.payable import Payable
from app.models.product import Product
from app.models.receivable import Receivable
from app.models.sale import Sale
from app.models.supplier import Supplier
from app.models.user import User
from app.services.access_control import user_has_permission


MAX_RESULTS = 5


def _text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, (datetime, date)):
        return value.strftime("%d/%m/%Y %H:%M") if isinstance(value, datetime) else value.strftime("%d/%m/%Y")
    if isinstance(value, Decimal):
        return f"{value:.2f}".replace(".", ",")
    return str(value)


def _normalize(value: str) -> str:
    replacements = str.maketrans("áàãâéêíóôõúçÁÀÃÂÉÊÍÓÔÕÚÇ", "aaaaeeioooucAAAAEEIOOOUC")
    return value.translate(replacements).lower()


def _search_term(message: str, labels: tuple[str, ...]) -> str | None:
    quoted = re.search(r'["“](.{2,80}?)["”]', message)
    if quoted:
        return quoted.group(1).strip()
    label_pattern = "|".join(re.escape(label) for label in labels)
    match = re.search(rf"(?:{label_pattern})\s+(?:de\s+|do\s+|da\s+)?([\wÀ-ÿ][\wÀ-ÿ .'-]{{1,79}})", message, re.IGNORECASE)
    if match:
        value = re.split(r"\s+(?:na|no|em|com|para|que|tem|esta|está)\s+", match.group(1), maxsplit=1, flags=re.IGNORECASE)[0]
        value = re.sub(r"^(?:cliente|clientes|fornecedor|fornecedores|conta|contas)\s+", "", value, flags=re.IGNORECASE)
        value = re.sub(r"^(?:com|que|tem|de|do|da|dos|das)\s+", "", value, flags=re.IGNORECASE)
        if _normalize(value) in {
            "crediario", "crediario aberto", "conta aberta", "contas abertas",
            "saldo", "extrato", "aberto", "em aberto", "todos", "todas",
        }:
            return None
        return value.strip(" .,:;?!") or None
    return None


def _has_any(db: Session, user: User, *permissions: str) -> bool:
    return any(user_has_permission(db, user, permission) for permission in permissions)


def _client_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "clients:view"):
        return "Consulta de clientes bloqueada: o usuário não possui permissão de leitura de clientes."
    term = _search_term(message, ("cliente", "clientes"))
    query = select(Client).where(Client.active.is_(True)).order_by(Client.name)
    if term:
        like = f"%{term}%"
        query = query.where(or_(Client.name.ilike(like), Client.trade_name.ilike(like), Client.document_number.ilike(like)))
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhum cliente encontrado com os filtros informados."
    lines = [f"Clientes autorizados encontrados ({len(rows)} exibidos, máximo {MAX_RESULTS}):"]
    for row in rows:
        contact = row.email or row.mobile_phone or row.phone or "sem contato cadastrado"
        lines.append(f"- {row.name} | documento: {row.document_number or 'não informado'} | contato: {contact}")
    return "\n".join(lines)


def _supplier_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "suppliers:view", "finance:payables:view"):
        return "Consulta de fornecedores bloqueada: o usuário não possui permissão de leitura de fornecedores."
    term = _search_term(message, ("fornecedor", "fornecedores"))
    query = select(Supplier).where(Supplier.active.is_(True)).order_by(Supplier.name)
    if term:
        like = f"%{term}%"
        query = query.where(or_(Supplier.name.ilike(like), Supplier.trade_name.ilike(like), Supplier.document_number.ilike(like)))
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhum fornecedor encontrado com os filtros informados."
    lines = [f"Fornecedores autorizados encontrados ({len(rows)} exibidos, máximo {MAX_RESULTS}):"]
    for row in rows:
        lines.append(f"- {row.name} | documento: {row.document_number or 'não informado'} | cidade/UF: {(row.city or 'não informada')}/{row.state or '--'}")
    return "\n".join(lines)


def _product_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "products:view", "stock:view"):
        return "Consulta de produtos/estoque bloqueada: o usuário não possui permissão de leitura."
    term = _search_term(message, ("produto", "produtos", "item", "itens"))
    query = select(Product).where(Product.active.is_(True)).order_by(Product.name)
    if term:
        like = f"%{term}%"
        query = query.where(or_(Product.name.ilike(like), Product.internal_code.ilike(like), Product.barcode.ilike(like)))
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhum produto encontrado com os filtros informados."
    lines = [f"Produtos autorizados encontrados ({len(rows)} exibidos, máximo {MAX_RESULTS}):"]
    for row in rows:
        lines.append(f"- {row.name} | unidade: {row.unit} | estoque: {_text(row.stock_quantity)} | preço: R$ {_text(row.sale_price)} | NCM: {row.ncm or 'não informado'}")
    return "\n".join(lines)


def _receivable_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "finance:view", "finance:receivables:view"):
        return "Consulta de contas a receber bloqueada: o usuário não possui permissão de leitura financeira."
    term = _search_term(message, ("cliente", "clientes", "extrato", "conta", "crediário", "crediario"))
    normalized = _normalize(message)
    open_only = any(term in normalized for term in ("aberto", "em aberto", "crediario aberto"))
    base_filters = [Receivable.status != "canceled"]
    if open_only:
        # O ERP usa status legados diferentes em algumas bases. Saldo positivo
        # é a fonte de verdade para "em aberto"; somente cancelados ficam fora.
        base_filters.append(Receivable.balance_amount > 0)
    query = select(Receivable).where(*base_filters).order_by(Receivable.created_at.desc(), Receivable.id.desc())
    if term:
        query = query.join(Client, Client.id == Receivable.client_id).where(or_(Client.name.ilike(f"%{term}%"), Receivable.number.ilike(f"%{term}%")))
    total_query = select(
        func.count(Receivable.id),
        func.coalesce(func.sum(Receivable.balance_amount), 0),
    ).where(*base_filters)
    if term:
        total_query = total_query.join(Client, Client.id == Receivable.client_id).where(
            or_(Client.name.ilike(f"%{term}%"), Receivable.number.ilike(f"%{term}%"))
        )
    total_count, total_balance = db.execute(total_query).one()
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhuma conta a receber encontrada com os filtros informados."
    state_label = "em aberto" if open_only else "encontradas"
    lines = [
        f"Há {total_count} conta(s) a receber {state_label}, com saldo total de R$ {_text(total_balance)}.",
        f"Mostrando {len(rows)} registro(s), máximo {MAX_RESULTS}:",
    ]
    for row in rows:
        client_name = row.client.name if row.client is not None else "sem cliente"
        lines.append(f"- {row.number or f'CR{row.id}'} | {client_name} | status: {row.status} | saldo: R$ {_text(row.balance_amount)} | vencimento: {_text(row.due_date) or 'não informado'}")
    return "\n".join(lines)


def _payable_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "finance:view", "finance:payables:view"):
        return "Consulta de contas a pagar bloqueada: o usuário não possui permissão financeira."
    term = _search_term(message, ("fornecedor", "fornecedores", "conta", "contas"))
    query = select(Payable).where(Payable.status != "canceled").order_by(Payable.created_at.desc(), Payable.id.desc())
    if term:
        query = query.join(Supplier, Supplier.id == Payable.supplier_id).where(or_(Supplier.name.ilike(f"%{term}%"), Payable.number.ilike(f"%{term}%")))
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhuma conta a pagar encontrada com os filtros informados."
    lines = [f"Contas a pagar autorizadas ({len(rows)} exibidas, máximo {MAX_RESULTS}):"]
    for row in rows:
        supplier_name = row.supplier.name if row.supplier is not None else "sem fornecedor"
        lines.append(f"- {row.number or f'CP{row.id}'} | {supplier_name} | status: {row.status} | saldo: R$ {_text(row.balance_amount)} | vencimento: {_text(row.due_date) or 'não informado'}")
    return "\n".join(lines)


def _fiscal_context(db: Session, user: User, message: str) -> str | None:
    if not _has_any(db, user, "fiscal:view", "fiscal:documents:view"):
        return "Consulta fiscal bloqueada: o usuário não possui permissão para visualizar documentos fiscais."
    normalized = _normalize(message)
    term = _search_term(message, ("nota", "nfe", "nfce", "nfse"))
    query = select(FiscalDocument).order_by(FiscalDocument.created_at.desc(), FiscalDocument.id.desc())
    if term and term.isdigit():
        query = query.where(FiscalDocument.number == int(term))
    elif "rejeitad" in normalized or "sefaz" in normalized:
        query = query.where(FiscalDocument.status.in_(["rejected", "rejeitada", "rejeitado"]))
    rows = list(db.scalars(query.limit(MAX_RESULTS)).all())
    if not rows:
        return "Nenhum documento fiscal encontrado com os filtros informados."
    lines = [f"Documentos fiscais autorizados ({len(rows)} exibidos, máximo {MAX_RESULTS}):"]
    for row in rows:
        reason = row.sefaz_message or "sem mensagem da SEFAZ"
        lines.append(f"- {row.document_type.upper()} nº {row.number or 'sem número'} | status: {row.status} | ambiente: {row.environment} | retorno: {reason[:220]}")
    return "\n".join(lines)


def build_authorized_context(db: Session, user: User, message: str, screen: str = "", module: str = "") -> str:
    """Return only the minimum read-only data relevant to the current request."""
    area = _normalize(f"{message} {screen} {module}")
    sections: list[str] = []
    if any(term in area for term in ("financeiro", "extrato", "crediario", "conta a receber", "recebivel")):
        result = _receivable_context(db, user, message)
        if result:
            sections.append(result)
    elif any(term in area for term in ("conta a pagar", "fornecedor", "fornecedores", "pagar")):
        result = _payable_context(db, user, message)
        if result:
            sections.append(result)
    elif any(term in area for term in ("nota fiscal", "nfe", "nfce", "nfse", "sefaz", "rejeitad", "fiscal")):
        result = _fiscal_context(db, user, message)
        if result:
            sections.append(result)
    elif any(term in area for term in ("produto", "produtos", "estoque", "entrada", "item")):
        result = _product_context(db, user, message)
        if result:
            sections.append(result)
    elif any(term in area for term in ("cliente", "clientes")):
        result = _client_context(db, user, message)
        if result:
            sections.append(result)
    if not sections:
        return "Nenhum dado operacional foi consultado. Responda somente com a documentação autorizada e o contexto da tela."
    return "\n\n".join(sections)

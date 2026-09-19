"""Small, deterministic retrieval layer used before the Lyna model.

The model never receives the whole database. This module selects a few safe,
curated notes based on the question and current screen.
"""

from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class KnowledgeNote:
    title: str
    keywords: frozenset[str]
    content: str


_NOTES = (
    KnowledgeNote(
        title="Escopo da Lyna",
        keywords=frozenset({"lyna", "sistema", "ajudar", "consegue", "sabe"}),
        content=(
            "A Lyna pode explicar a tela atual, orientar fluxos e interpretar "
            "dados autorizados. Ela não altera registros e não substitui o "
            "motor fiscal determinístico."
        ),
    ),
    KnowledgeNote(
        title="Rejeição fiscal",
        keywords=frozenset({"rejeição", "rejeitado", "sefaz", "erro", "nota", "nf-e", "nfc-e", "nfse"}),
        content=(
            "Para explicar uma rejeição, considere sempre o código e a mensagem "
            "retornados pela SEFAZ, o XML enviado e os campos destacados. A "
            "correção deve ser feita no documento em revisão e validada pelo "
            "motor fiscal antes de novo envio. Nunca invente uma causa quando "
            "o retorno oficial não estiver disponível."
        ),
    ),
    KnowledgeNote(
        title="Motor fiscal",
        keywords=frozenset({"cfop", "cst", "csosn", "ncm", "tributação", "ib", "cbs", "fiscal"}),
        content=(
            "A tributação da saída é recalculada pelo motor fiscal conforme "
            "emitente, regime, natureza, destino, produto e data. Dados da "
            "entrada podem ser referência histórica, mas não devem ser copiados "
            "automaticamente para a saída."
        ),
    ),
    KnowledgeNote(
        title="Financeiro",
        keywords=frozenset({"financeiro", "crediário", "receber", "baixa", "extrato", "cliente"}),
        content=(
            "No financeiro, a Lyna deve explicar situação, datas, valores e "
            "histórico somente com dados retornados pela API da empresa atual. "
            "Ela não deve dar baixa, reabrir ou editar títulos sem uma ação "
            "explícita e confirmação posterior."
        ),
    ),
    KnowledgeNote(
        title="Estoque e entrada",
        keywords=frozenset({"estoque", "entrada", "fornecedor", "produto", "xml"}),
        content=(
            "A entrada pode atualizar estoque e guardar os dados originais do "
            "XML. Informações fiscais de entrada não determinam sozinhas a "
            "tributação da venda."
        ),
    ),
)


def retrieve_knowledge(message: str, screen: str = "", module: str = "", limit: int = 3) -> list[KnowledgeNote]:
    """Return the most relevant curated notes without touching the database."""

    query = _normalize(" ".join((message, screen, module)))
    tokens = set(query.split())
    scored: list[tuple[int, KnowledgeNote]] = []
    for note in _NOTES:
        score = len(tokens.intersection({_normalize(keyword) for keyword in note.keywords}))
        if score:
            scored.append((score, note))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [note for _, note in scored[:limit]]


def format_knowledge(notes: list[KnowledgeNote]) -> str:
    if not notes:
        return "Nenhuma nota específica da base interna foi encontrada."
    return "\n".join(f"- {note.title}: {note.content}" for note in notes)


def _normalize(value: str) -> str:
    value = value.lower().replace("ç", "c").replace("ã", "a").replace("á", "a")
    value = value.replace("é", "e").replace("í", "i").replace("ó", "o")
    value = value.replace("ú", "u")
    return re.sub(r"[^a-z0-9]+", " ", value).strip()

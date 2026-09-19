"""Small, deterministic retrieval layer used before the Lyna model.

The model never receives the whole database. This module selects a few safe,
curated notes based on the question and current screen.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import re


@dataclass(frozen=True)
class KnowledgeNote:
    title: str
    keywords: frozenset[str]
    content: str
    sources: tuple[str, ...] = ()


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
        sources=("https://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=ee%2FBnNosTWA%3D",),
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
        sources=(),
    ),
    KnowledgeNote(
        title="Rejeições 518, 519 e 531",
        keywords=frozenset({"518", "519", "531", "cfop", "entrada", "saida", "base", "icms", "rejeicao"}),
        content=(
            "518 indica CFOP de entrada em NF-e de saída; 519 indica CFOP de saída em NF-e de entrada; "
            "531 indica divergência no total da base de cálculo do ICMS. A mensagem oficial, o XML e o "
            "documento revisado continuam sendo a fonte final para a correção."
        ),
        sources=("https://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=ee%2FBnNosTWA%3D",),
    ),
    KnowledgeNote(
        title="IBS/CBS e atualização normativa",
        keywords=frozenset({"ibs", "cbs", "reforma", "2026", "2027", "simples", "mei", "vigente"}),
        content=(
            "IBS/CBS não devem ser copiados da entrada para a saída. O motor deve recalcular a tributação "
            "pela empresa emitente, regime, operação, destino, produto e data. Como a regulamentação e as "
            "validações mudam, a Lyna deve citar a fonte atual e nunca transformar uma pesquisa em regra automática."
        ),
        sources=(
            "https://www.gov.br/receitafederal/pt-br/assuntos/reforma-tributaria-do-consumo/orientacoes-2026",
            "https://www.gov.br/receitafederal/pt-br/assuntos/reforma-tributaria-do-consumo/reforma-de-fato",
        ),
    ),
    KnowledgeNote(
        title="NFS-e padrão nacional",
        keywords=frozenset({"nfse", "nfs e", "servico", "servicos", "municipal", "nacional"}),
        content=(
            "A NFS-e tem documentação técnica e regras próprias do padrão nacional. A Lyna deve "
            "explicar o preenchimento com base na documentação atual e no município/ambiente da emissão, "
            "sem afirmar que uma regra de NF-e de mercadoria vale automaticamente para serviço."
        ),
        sources=(
            "https://www.gov.br/nfse/pt-br",
            "https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica",
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
    KnowledgeNote(
        title="NCM oficial e referências fiscais do Lyncar",
        keywords=frozenset({"ncm", "cest", "cfop", "cclasstrib", "classificacao", "produto"}),
        content=(
            "Para sugestões, o Lyncar usa a base mestre fiscal sincronizada com referências oficiais "
            "(incluindo NCM do Portal Único Siscomex/Classif), além do cadastro e do motor fiscal. "
            "A sugestão nunca altera o produto ou a nota automaticamente; a pessoa revisa e confirma."
        ),
        sources=(
            "https://www.gov.br/siscomex/pt-br/servicos/classificacao-fiscal-de-mercadorias",
            "https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica",
        ),
    ),
)


@lru_cache(maxsize=256)
def _retrieve_cached(query: str, limit: int) -> tuple[KnowledgeNote, ...]:
    tokens = set(query.split())
    scored: list[tuple[int, KnowledgeNote]] = []
    for note in _NOTES:
        keywords = {_normalize(keyword) for keyword in note.keywords}
        score = len(tokens.intersection(keywords))
        if any(keyword in query for keyword in keywords if len(keyword) > 3):
            score += 1
        if score:
            scored.append((score, note))
    scored.sort(key=lambda item: item[0], reverse=True)
    return tuple(note for _, note in scored[:limit])


def retrieve_knowledge(message: str, screen: str = "", module: str = "", limit: int = 3) -> list[KnowledgeNote]:
    """Return the most relevant curated notes without touching the database."""

    query = _normalize(" ".join((message, screen, module)))
    return list(_retrieve_cached(query, max(1, min(limit, 8))))


def format_knowledge(notes: list[KnowledgeNote]) -> str:
    if not notes:
        return "Nenhuma nota específica da base interna foi encontrada."
    lines: list[str] = []
    for note in notes:
        lines.append(f"- {note.title}: {note.content}")
        if note.sources:
            lines.append("  Fontes: " + ", ".join(note.sources))
    return "\n".join(lines)


def _normalize(value: str) -> str:
    value = value.lower().replace("ç", "c").replace("ã", "a").replace("á", "a")
    value = value.replace("é", "e").replace("í", "i").replace("ó", "o")
    value = value.replace("ú", "u")
    return re.sub(r"[^a-z0-9]+", " ", value).strip()

"""Versioned source catalog for Lyna's retrieval policy.

This is a catalog, not a blind web scraper. Ingestion jobs can later download
structured official material into the master reference database while keeping
authority, jurisdiction and validity visible to the answer layer.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class KnowledgeSource:
    key: str
    title: str
    url: str
    category: str
    authority: str
    format_hint: str
    refresh: str
    jurisdiction: str = "BR"


SOURCES: tuple[KnowledgeSource, ...] = (
    KnowledgeSource("nfe_portal", "Portal Nacional NF-e/NFC-e", "https://www.nfe.fazenda.gov.br/portal/", "fiscal/nfe", "official", "HTML/PDF/XML", "weekly"),
    KnowledgeSource("nfse_portal", "Portal Nacional NFS-e", "https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual", "fiscal/nfse", "official", "HTML/PDF/XSD", "weekly"),
    KnowledgeSource("classif_ncm", "Sistema Classif / NCM", "https://www.gov.br/receitafederal/pt-br/assuntos/aduana-e-comercio-exterior/classificacao-fiscal-de-mercadorias/classif", "fiscal/ncm", "official", "JSON/HTML", "monthly"),
    KnowledgeSource("classif_consultas", "Consultas de classificação fiscal", "https://www.gov.br/receitafederal/pt-br/assuntos/aduana-e-comercio-exterior/classificacao-fiscal-de-mercadorias/consultas", "fiscal/ncm", "official", "HTML/PDF", "monthly"),
    KnowledgeSource("sped", "SPED - manuais e guias", "https://sped.rfb.gov.br/item/show/1573", "fiscal/sped", "official", "PDF/HTML", "monthly"),
    KnowledgeSource("confaz", "CONFAZ - legislação e manuais", "https://www.confaz.fazenda.gov.br/", "fiscal/confaz", "official", "HTML/PDF", "weekly"),
    KnowledgeSource("receita_reforma", "Receita Federal - Reforma Tributária", "https://www.gov.br/receitafederal/pt-br/assuntos/reforma-tributaria-do-consumo/orientacoes-2026", "fiscal/ibs_cbs", "official", "HTML/PDF", "weekly"),
    KnowledgeSource("simples_mei", "Empresas e Negócios - Simples/MEI", "https://www.gov.br/empresas-e-negocios/pt-br/empreendedor/legislacao", "fiscal/simples_mei", "official", "HTML/PDF", "monthly"),
    KnowledgeSource("cnae", "IBGE CONCLA / CNAE", "https://cnae.ibge.gov.br/", "fiscal/cnae", "official", "HTML", "quarterly"),
    KnowledgeSource("pix", "Banco Central - normas Pix", "https://www.bcb.gov.br/estabilidadefinanceira/pix-normas", "financeiro/pix", "official", "HTML/PDF", "monthly"),
    KnowledgeSource("postgres", "PostgreSQL documentation", "https://www.postgresql.org/docs/18/ddl.html", "tecnico/postgres", "technical_official", "HTML", "monthly"),
    KnowledgeSource("owasp", "OWASP Cheat Sheet Series", "https://cheatsheetseries.owasp.org/", "tecnico/security", "technical_official", "HTML", "monthly"),
    KnowledgeSource("massive", "MASSIVE - Amazon Science", "https://www.amazon.science/code-and-datasets/massive", "nlu/general", "open_dataset", "JSON/Parquet", "one_time"),
    KnowledgeSource("sid_ptbr", "SID - intenções em português", "https://huggingface.co/datasets/luigicfilho/sid", "nlu/pt_br", "open_dataset", "Parquet", "one_time"),
    KnowledgeSource("customer_service_ptbr", "Brazilian Customer Service Conversations", "https://huggingface.co/datasets/RichardSakaguchiMS/brazilian-customer-service-conversations", "nlu/pt_br", "open_dataset", "JSON/Parquet", "one_time"),
    KnowledgeSource("talkex_ptbr", "TalkEx PT-BR", "https://huggingface.co/datasets/paulohenriquevn/talkex-augmented-pt-br", "nlu/pt_br", "open_dataset", "JSON/Parquet", "one_time"),
    KnowledgeSource("speech_acts_ptbr", "Atos de Fala PT-BR", "https://huggingface.co/lucianfialho/atos-de-fala-ptbr", "nlu/pt_br", "open_dataset", "JSON/Parquet", "one_time"),
)


def sources_for(category: str | None = None) -> tuple[KnowledgeSource, ...]:
    if not category:
        return SOURCES
    return tuple(source for source in SOURCES if source.category.startswith(category))


def official_sources_for(category: str | None = None) -> tuple[KnowledgeSource, ...]:
    return tuple(source for source in sources_for(category) if source.authority in {"official", "technical_official"})

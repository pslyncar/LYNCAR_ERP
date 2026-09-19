"""Compact, deterministic help for the main Lyncar modules."""

from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class ModuleGuide:
    name: str
    keywords: tuple[str, ...]
    text: str


GUIDES = (
    ModuleGuide("Financeiro", ("financeiro", "crediario", "conta a receber", "conta a pagar", "extrato", "baixa"), "No Financeiro você acompanha contas a receber e a pagar, extratos, histórico, baixas e prioridades. A Lyna pode consultar dados autorizados e explicar o fluxo, mas não altera títulos sem uma ação própria do sistema."),
    ModuleGuide("Vendas", ("venda", "vendas", "orcamento", "pedido"), "Em Vendas você registra vendas, escolhe cliente, produtos, quantidades e forma de pagamento. Vendas a prazo podem gerar contas no Financeiro conforme a condição escolhida."),
    ModuleGuide("PDV", ("pdv", "caixa", "cupom", "sangria", "fechamento de caixa"), "No PDV você realiza vendas rápidas, recebe pagamentos, imprime o documento fiscal configurado e acompanha abertura, sangria e fechamento do caixa."),
    ModuleGuide("Estoque e entradas", ("estoque", "entrada", "mercadoria", "xml", "produto", "inventario"), "Em Estoque e Entradas você cadastra produtos, importa XML, confere fornecedores, movimenta quantidades e acompanha custo médio. A entrada não define automaticamente a tributação da saída."),
    ModuleGuide("Clientes e fornecedores", ("cliente", "clientes", "fornecedor", "fornecedores", "cadastro"), "Nos cadastros você consulta e mantém clientes e fornecedores. Dados só aparecem conforme a permissão do usuário e a empresa da sessão."),
    ModuleGuide("Notas fiscais", ("nota fiscal", "nfe", "nfce", "nfse", "sefaz", "rejeicao", "rejeitada", "cfop", "ncm", "cst"), "Em Notas Fiscais você prepara, revisa, pré-valida, transmite e acompanha NF-e, NFC-e e NFS-e conforme o ambiente configurado. O motor fiscal recalcula a saída e a mensagem oficial da SEFAZ é a referência para rejeições."),
    ModuleGuide("Configurações e permissões", ("configuracao", "configuracoes", "permissao", "acesso", "usuario", "empresa"), "Configurações controlam empresa, usuários, permissões, módulos e integrações. A Lyna respeita a permissão da sessão e não expõe dados de outra empresa."),
    ModuleGuide("PedeOn", ("pedeon", "cardapio", "pedido online", "catalogo", "entrega"), "No PedeOn você administra cardápio, categorias, produtos, pedidos, horários e canais públicos. O PedeOn é separado das telas de venda e PDV do ERP."),
)


def guide_for(message: str, screen: str = "", module: str = "") -> ModuleGuide | None:
    text = re.sub(r"[^a-z0-9 ]+", " ", f"{message} {screen} {module}".lower())
    ranked = [(sum(1 for keyword in guide.keywords if keyword in text), guide) for guide in GUIDES]
    ranked.sort(key=lambda item: item[0], reverse=True)
    return ranked[0][1] if ranked and ranked[0][0] else None

# 2026-07-13 - Regras fiscais de saida e PDV Windows

## Decisao

Foi criada uma camada de **regras fiscais de saida**, separada da tributacao importada por XML de entrada.

O XML de entrada continua alimentando cadastro, custo, estoque, NCM, CEST e historico da compra, mas nao deve copiar automaticamente CFOP/CST/CSOSN/aliquotas de entrada como regra de venda.

## Motivo

Grandes ERPs separam:

- dados de entrada/compra;
- cadastro do produto;
- regra fiscal de saida;
- motor de emissao fiscal.

A nota do fornecedor mostra como o fornecedor vendeu. A NFC-e/NF-e de saida depende do emitente, regime/CRT, modelo da nota, UF, operacao, produto/NCM/CEST e regra fiscal da empresa.

## Implementacao

Nova tabela:

- `fiscal_output_rules`

Nova tela:

- Configuracoes > Fiscal > Regras fiscais de saida

Motor:

- NFC-e e NF-e passam a resolver um perfil fiscal de saida antes de montar o XML.
- A regra sobrepoe campos somente durante a montagem do XML.
- O produto nao e alterado automaticamente.

## MEI / CRT 4

Para NFC-e modelo 65, o sistema protege CSOSN incompativel e deve usar somente codigos aceitos no modelo, como 102 ou 300, sempre com conferencia do contador.

## IBS/CBS/IS

As regras fiscais de saida ja possuem campos para IBS/CBS/IS.
Se houver regra/produto preenchido, o XML pode sair no novo padrao.
Se nao houver, producao continua usando o padrao antigo quando permitido.

## Entregas

- Atualizacao servidor: `outputs/ATUALIZACAO_FISCAL_SAIDA_PDV_2026-07-13`
- ZIP servidor: `outputs/ATUALIZACAO_FISCAL_SAIDA_PDV_2026-07-13.zip`
- Instalador PDV Windows: `outputs/PDV_LYNCAR_SETUP_BUILD_1.0.14/PDV_Lyncar_Setup_1.0.14.exe`

## Validacoes

- Python compileall: OK
- Flutter analyze: OK
- Build web release: OK
- Build Windows PDV release: OK
- Inno Setup: OK


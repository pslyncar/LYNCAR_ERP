# Fiscal: entrada x saída + IBS/CBS em homologação

Data: 2026-07-12

## Decisão

O Lyncar deve tratar XML de entrada e emissão de saída como coisas separadas.

- XML de entrada alimenta cadastro, custo, estoque, NCM, origem, unidade, conversão e histórico fiscal da compra.
- XML de entrada não deve copiar cegamente CFOP/CST/CSOSN/alíquotas para a tributação de saída.
- A saída deve ser resolvida pelo cadastro fiscal do produto + regra fiscal do emitente + modelo da nota + ambiente.

## MEI / CRT 4

Para empresa MEI/CRT 4 emitindo NFC-e modelo 65:

- A saída usa CSOSN válido para NFC-e.
- Caso o produto esteja sem CSOSN de saída, o motor resolve para CSOSN 102.
- CSOSN 400 vindo de XML de entrada fica como histórico de compra, não como regra automática de saída.

## IBS/CBS

A SEFAZ homologação SP rejeitou NFC-e sem IBS/CBS com código 1115.

Regra adotada:

- Em homologação, no ano de 2026, incluir IBS/CBS automaticamente quando necessário para passar validação da SEFAZ.
- Padrão de transição:
  - CST: 000
  - cClassTrib: 000001
  - IBS UF: 0,1000%
  - IBS Município: 0,0000%
  - CBS: 0,9000%
- Em produção, não forçar IBS/CBS para produto sem reforma tributária marcada.
- Se o produto tiver reforma tributária marcada e campos preenchidos, usar os dados do produto.

## Teste real feito

Banco tenant: `papezzosync_drika_padaria`

Configuração encontrada:

- Certificado A1 cadastrado
- CSC NFC-e cadastrado
- Ambiente homologação
- CRT 4 / MEI
- Cidade IBGE 3526704

Teste de ponta a ponta:

1. XML de entrada fictício:
   - NCM 22029900
   - CFOP entrada 5405
   - CSOSN entrada 400
2. Produto criado/atualizado com estoque e custo.
3. Produto ficou sem CSOSN de saída.
4. Motor resolveu saída:
   - CFOP 5102
   - CSOSN 102
   - IBS/CBS de homologação 2026
5. SEFAZ homologação autorizou:
   - cStat 100
   - protocolo 13526000008296841
   - chave 35260763816719000115650010000000561304059222

## Pacote gerado

`E:\ATUALIZACAO_FISCAL_ENTRADA_SAIDA_IBSCBS_HOMOLOGACAO_2026-07-12`

ZIP:

`E:\ATUALIZACAO_FISCAL_ENTRADA_SAIDA_IBSCBS_HOMOLOGACAO_2026-07-12.zip`

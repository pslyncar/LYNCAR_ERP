# 2026-06-30 - CNPJ e Assistente Fiscal funcional

Foi corrigida/completada a camada separada do Assistente Fiscal, sem mexer no Motor Fiscal.

## Consulta CNPJ
- Endpoint: `/master/companies/cnpj-lookup/{cnpj}`.
- O 404 visto no teste era API local antiga sem a rota carregada; apos restart a rota existe e sem token retorna 401.
- CNPJ 63816719000115 testado em consulta direta: BrasilAPI retorna MEI=true, Simples=true, regime sugerido `mei`, CRT `4`.

## Regra de sugestao
- CNPJ define perfil da empresa: regime/CRT.
- XML/historico define dados do produto: NCM, CFOP, CST/CSOSN, aliquotas, IBS/CBS/IS.
- Se nao houver historico/XML suficiente:
  - MEI -> CSOSN 400;
  - Simples Nacional -> CSOSN 102;
  - Regime normal -> CST ICMS 00;
  - origem padrao 0;
  - CFOP padrao 5102.
- Sempre como sugestao, com confirmacao do usuario/contador.

## XML de entrada
Parser NF-e passou a ler ICMS antigo/PIS/COFINS/IPI alem dos campos novos:
- origem, CST, CSOSN;
- pICMS, pPIS, pCOFINS, pIPI;
- IBS/CBS/IS ja existentes.

## Entrada de estoque
Itens de entrada ganharam campos para aprender fiscal antigo:
- origin, cst, csosn, icms_rate, pis_rate, cofins_rate, ipi_rate.

## Entrega
E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-30_CNPJ_E_ASSISTENTE_FISCAL_FUNCIONAL

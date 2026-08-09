# 2026-06-29 - Assistente Fiscal completo com fontes oficiais

## Decisao

A entrega valida para servidor passa a ser a consolidada:

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_ASSISTENTE_FISCAL_COMPLETO`

Zip:

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_ASSISTENTE_FISCAL_COMPLETO.zip`

Ela inclui a primeira versao do Assistente Fiscal Inteligente e a segunda parte com estrutura de fontes oficiais.

## Principio

O Assistente Fiscal Inteligente continua separado do Motor Fiscal.

Nao altera:

- emissao NF-e/NFC-e;
- assinatura XML;
- transmissao SEFAZ;
- cancelamento fiscal;
- arquivos `nfe_sp.py` e `nfce_sp.py`.

## Fontes usadas para sugestao/validacao

1. XMLs de NF-e importados e entradas confirmadas.
2. Produtos ja classificados pelo usuario.
3. Tabela NCM oficial local sincronizavel pelo Portal Unico Siscomex/Classif.
4. Tabela CFOP local sincronizavel por fonte oficial CONFAZ/Ajustes SINIEF.
5. Tabela CEST local sincronizavel por fonte oficial CONFAZ/Convenios ICMS 92/15 e 142/18.
6. Estrutura preparada para regras estaduais por UF.

## Tabelas auxiliares

- `fiscal_suggestions`
- `fiscal_reference_syncs`
- `fiscal_ncm_codes`
- `fiscal_cfop_codes`
- `fiscal_cest_codes`
- `fiscal_state_rules`

## Endpoints

- `GET /fiscal-assistant/product-suggestions`
- `GET /fiscal-assistant/reference/status`
- `POST /fiscal-assistant/reference/import`

## Script

`backend/scripts/sync_fiscal_sources.py`

Variaveis:

- `FISCAL_NCM_JSON_URL`
- `FISCAL_CFOP_CSV_URL`
- `FISCAL_CEST_CSV_URL`

## Aviso legal

“As informações fiscais são sugestões automáticas do sistema e devem ser conferidas pelo responsável fiscal ou contador da empresa.”

## Validacao

- Python compileall: OK
- dart format: OK
- flutter analyze: OK
- flutter build web: OK
- migracao local: OK

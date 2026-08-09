# 2026-06-29 - Custos protegidos e campos fiscais selecionaveis

## Decisao

No cadastro de produtos, os custos que normalmente sao alimentados pela nota/entrada/XML devem permanecer protegidos em produtos ja cadastrados:

- valor total da ultima compra;
- quantidade recebida na ultima compra;
- custo unitario da ultima compra;
- custo medio atual.

Ao clicar nesses campos, o ERP pergunta se o usuario realmente deseja liberar correcao manual. A edicao manual e uma excecao para corrigir cadastro/entrada feita errada. O fluxo normal continua vindo da nota fiscal/entrada.

## Regra backend

O backend passou a aceitar `average_cost` no payload de produto para permitir correcao manual controlada do custo medio.

- Se `average_cost` for alterado, o valor em estoque e recalculado usando esse custo medio.
- Se apenas total/quantidade da ultima compra forem alterados, o custo medio e recalculado pelo total dividido pela quantidade.
- Proximas entradas/notas continuam atualizando os custos normalmente.

## Fiscal

Campos fiscais que seguem tabela passaram a ser seletores no cadastro do produto:

- CFOP venda;
- Origem;
- CST ICMS;
- CSOSN;
- CST IBS/CBS.

NCM e CEST continuam editaveis por enquanto, pois a base completa deve ser mantida a partir de fonte oficial ou tabela sincronizada no backend. A evolucao recomendada e criar busca fiscal/autocomplete no backend, usando fonte oficial atualizada, para pesquisar NCM por codigo ou descricao.

## Entrega

Pacote gerado em:

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_CUSTO_BLOQUEADO_E_FISCAL_SELECIONAVEL`

Zip:

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_CUSTO_BLOQUEADO_E_FISCAL_SELECIONAVEL.zip`

## Validacao

- Python compileall: OK
- dart format: OK
- flutter analyze: OK
- flutter build web --release: OK

# 2026-08-11 - Segmentos cadastraveis no Master

## Decisao

Segmentos comerciais deixam de ser uma lista fixa apenas no codigo e passam a existir no banco master.

## Regra

- O Master pode criar, editar, ativar/desativar e excluir segmentos.
- Cada segmento possui modulos sugeridos.
- O plano continua sendo a base comercial do contrato.
- Ao cadastrar ou trocar segmento no cliente, o sistema sugere os modulos do segmento combinados com os modulos do plano.
- O Master pode alterar manualmente os modulos do cliente depois da sugestao.
- Alterar manualmente os modulos do cliente nao muda o segmento para Personalizado.
- Segmentos em uso por clientes nao podem ser excluidos; devem ser desativados ou os clientes devem ser alterados antes.

## Migracao

Nova tabela no banco master:

- `business_segments`

Campos principais:

- `code`
- `name`
- `description`
- `default_modules`
- `active`
- `sort_order`

Os segmentos atuais sao semeados automaticamente:

- `assistencia_papezzo`
- `assistencia_tecnica`
- `mercado`
- `padaria`
- `loja`
- `custom`

## Observacao

Chaves tecnicas devem preferir texto sem acento, por exemplo `assistencia_tecnica`.
Foi mantida compatibilidade para clientes antigos que possam ter `assistencia_técnica`.

## Atencao para atualizar o servidor

Antes de aplicar em producao, fazer backup do projeto e dump do banco master.

Passos esperados:

- `git fetch origin main`
- revisar commits novos antes do pull
- fazer backup/dump
- `git pull origin main`
- rodar a migracao master: `python -m app.migrate_master` a partir da pasta `backend`
- rodar o processo normal de build/restart do servidor
- abrir o Master em Planos e Segmentos e conferir cada plano
- conferir clientes ativos de cada plano, principalmente clientes Start/Pro que tenham excecoes manuais de modulo

A migracao cria a tabela `business_segments` e semeia os segmentos atuais.

Tambem existe migracao de compatibilidade para os novos modulos de menu lateral:

- `stock_entries` para Entradas de estoque
- `stock_withdrawals` para Baixas de estoque
- `cash_closings` para Caixa/fechamento
- `support` para Suporte
- `settings` para Configuracoes

Essa compatibilidade completa planos, segmentos e clientes antigos uma vez, quando o banco ainda nao possui esses modulos nos planos. Depois disso, alteracoes nos planos devem ser feitas pelo Master, porque mudar um plano propaga para todos os clientes daquele plano.

## Ajuste 2026-08-11 - Seed somente em banco vazio

Os seeds de planos e segmentos agora servem apenas para instalacao nova, quando a tabela ainda esta vazia.

Em producao madura, o Master passa a ser a fonte principal:

- apagar um plano nao faz o codigo recriar automaticamente depois
- apagar um segmento nao faz o codigo recriar automaticamente depois
- editar modulos/precos/limites deve ser feito pelo Master
- migracao continua segura para banco novo, mas nao sobrescreve a administracao real do banco existente

Para o servidor: depois do pull, rodar a migracao normalmente. Se as tabelas ja tiverem dados, o seed nao vai recriar receitas de fabrica apagadas manualmente.

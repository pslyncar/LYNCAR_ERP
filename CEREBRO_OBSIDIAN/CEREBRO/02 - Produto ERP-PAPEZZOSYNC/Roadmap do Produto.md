# Roadmap do Produto

Este roadmap foi atualizado com base no estado real encontrado no codigo e na documentacao do repositorio.

## Fase 1 - Fundacao

Status: implementada no codigo.

- Backend FastAPI criado.
- Configuracao de banco via SQLAlchemy.
- `db_init.py` cria tabelas com `Base.metadata.create_all`.
- `migrate_local.py` aplica evolucoes locais e semeia controle de acesso.
- Endpoints de clientes e equipamentos existem.

## Fase 2 - Chamados

Status: implementada no backend.

- Endpoints de chamados existem.
- Filtros por cliente, equipamento, status e prioridade existem.
- Regras de vinculo validam cliente, equipamento e tecnico responsavel.
- `closed_at` e preenchido quando chamado passa para `concluido` ou `cancelado`.

## Fase 3 - Agente de monitoramento

Status: implementada no codigo.

- Agente Python existe.
- Coleta CPU, memoria, disco, volumes, temperatura, hostname, sistema operacional, IP e versao.
- Envia snapshots para a API com token do agente.
- Backend atualiza `last_seen_at`, identidade do equipamento, status atual e alertas.
- Scripts de instalacao Windows e empacotamento existem.

## Fase 4 - Dashboard

Status: implementada no backend e no app Flutter.

- Endpoint `/dashboard/summary`.
- Conta clientes, equipamentos, maquinas online/offline, chamados por status e alertas abertos.
- Online/offline usa limite de 5 minutos a partir de `last_seen_at`.

## Fase 5 - Interface Flutter

Status: implementada para app administrativo.

- App Flutter criado.
- Login implementado.
- Dashboard implementado.
- Telas encontradas: clientes, maquinas, OS, vendas, PDV, produtos, operadores PDV e usuarios.
- Menu lateral respeita permissoes da sessao.

## Fase 6 - Relatorios

Status: nao determinado no codigo analisado.

- Existe permissao `reports:view`.
- Nao foi encontrada tela ou rota especifica de relatorios.
- Relatorios por cliente, relatorio mensal e exportacao PDF permanecem sem implementacao confirmada.

## Funcionalidades alem do roadmap inicial encontradas

- Produtos com dados fiscais, estoque, codigos e busca por codigo.
- Ordens de servico com itens, totais, status de workflow e impressao termica.
- Vendas/PDV com pagamento, troco, desconto, cancelamento e baixa/estorno de estoque.
- Operadores PDV com permissoes para abrir caixa, sangria, cancelamento e desconto.
- Controle de usuarios, roles, permissoes e overrides.

## Proximos itens sugeridos a documentar

- Relatorios.
- Portal/app do cliente.
- Financeiro/contratos.
- Estrategia formal de migracoes.
- Criterios de aceite por modulo.

# AGENTS.md - ERP-PAPEZZOSYNC Knowledge Vault

Este Vault do Obsidian e a fonte principal de conhecimento do projeto ERP-PAPEZZOSYNC.

Qualquer agente de IA que trabalhe neste projeto deve consultar este Vault antes de responder, planejar ou modificar codigo relacionado ao ERP-PAPEZZOSYNC.

## Objetivo do Vault

Manter uma base de conhecimento permanente, consistente e atualizada sobre:

- Produto ERP-PAPEZZOSYNC.
- Backend FastAPI.
- Banco de dados.
- App administrativo Flutter.
- Agente Windows de monitoramento.
- Modulos do sistema.
- Regras de negocio.
- API e endpoints.
- Operacao local.
- Roadmap, backlog, bugs, funcionalidades e decisoes tecnicas.

## Regra principal

Antes de criar qualquer informacao nova, consulte primeiro a documentacao existente.

Ordem recomendada de consulta:

1. `Dashboard Principal.md`
2. `01 - Visao Geral/Mapa do Projeto.md`
3. `01 - Visao Geral/Resumo Executivo.md`
4. Notas especificas da area afetada.
5. `09 - Regras de Negocio/Regras de Negocio.md`
6. `12 - Roadmap e Tarefas/Roadmap do Projeto.md`
7. `12 - Roadmap e Tarefas/Backlog de Funcionalidades.md`
8. `13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas.md`

## Evitar duplicidade

Nao crie documentacao duplicada.

Antes de criar uma nova nota:

1. Pesquise se ja existe nota sobre o mesmo assunto.
2. Atualize a nota existente quando o assunto for continuidade ou complemento.
3. Crie uma nova nota apenas quando o assunto tiver escopo proprio.
4. Sempre adicione links internos para notas relacionadas.

Se houver informacoes conflitantes, nao escolha silenciosamente uma delas. Registre a divergencia e proponha consolidacao.

## Areas oficiais do Vault

Use estas areas como destino preferencial:

- `00 - Entrada/Inbox.md`: ideias temporarias e informacoes ainda nao classificadas.
- `00 - Entrada/Templates/`: modelos para novas notas.
- `01 - Visao Geral/`: contexto geral do projeto.
- `02 - Produto ERP-PAPEZZOSYNC/`: produto, MVP e roadmap de produto.
- `03 - Arquitetura/`: arquitetura geral e integracoes.
- `04 - Backend FastAPI/`: API, backend, autenticacao e servicos.
- `05 - Banco de Dados/`: modelo de dados, tabelas e evolucao do schema.
- `06 - App Admin Flutter/`: interface administrativa Flutter.
- `07 - Agente Windows/`: agente Python de monitoramento.
- `08 - Modulos do Sistema/`: documentacao por modulo funcional.
- `09 - Regras de Negocio/`: regras permanentes do negocio.
- `10 - API e Endpoints/`: mapa e detalhes de endpoints.
- `11 - Operacao e Deploy/`: execucao local, deploy e operacao.
- `12 - Roadmap e Tarefas/`: roadmap, backlog, bugs e funcionalidades.
- `13 - Decisoes Tecnicas/`: decisoes tecnicas importantes.
- `99 - Arquivo/`: material obsoleto ou arquivado, somente com autorizacao.

## Consistencia obrigatoria

Mantenha consistencia entre:

- Backend FastAPI.
- Banco de dados.
- App Admin Flutter.
- Agente Windows.
- Documentacao do Vault.
- Documentacao do repositorio ERP-PAPEZZOSYNC.

Quando uma mudanca afetar mais de uma camada, atualize todas as notas relacionadas.

Exemplos:

- Novo campo no banco: atualizar `05 - Banco de Dados/Modelo de Dados.md`, endpoints relacionados e modulo funcional.
- Novo endpoint: atualizar `10 - API e Endpoints/Mapa de Endpoints.md`, backend e modulo correspondente.
- Nova tela Flutter: atualizar `06 - App Admin Flutter/App Admin Flutter.md` e modulo correspondente.
- Nova regra de permissao: atualizar `09 - Regras de Negocio/Regras de Negocio.md` e `08 - Modulos do Sistema/Usuarios e Permissoes.md`.
- Mudanca no agente: atualizar `07 - Agente Windows/Agente de Monitoramento.md`, regras de privacidade e endpoints de monitoramento.

## Decisoes tecnicas

Registre automaticamente decisoes tecnicas importantes em:

`13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas.md`

Use tambem o template:

`00 - Entrada/Templates/Template - Decisao Tecnica.md`

Uma decisao tecnica deve ser registrada quando envolver:

- Arquitetura.
- Banco de dados.
- Frameworks, bibliotecas ou linguagens.
- Autenticacao e seguranca.
- Permissoes.
- Integracoes.
- Deploy.
- Padroes de API.
- Coleta de dados pelo agente.
- Mudancas com impacto futuro de manutencao.

Cada decisao deve conter:

- Status.
- Contexto.
- Decisao.
- Consequencias.
- Alternativas consideradas, quando aplicavel.
- Links para codigo, modulo ou regra relacionada.

## Funcionalidades implementadas

Registre novas funcionalidades implementadas em:

`12 - Roadmap e Tarefas/Funcionalidades/Funcionalidades Implementadas.md`

Para funcionalidades maiores, crie uma nota propria usando:

`00 - Entrada/Templates/Template - Funcionalidade.md`

Ao registrar uma funcionalidade, documente:

- Modulo afetado.
- Objetivo.
- Comportamento esperado.
- Regras de negocio.
- Backend envolvido.
- Frontend envolvido.
- Banco de dados envolvido.
- Como validar.
- Links para notas relacionadas.

Atualize tambem:

- Modulo em `08 - Modulos do Sistema/`.
- Endpoints em `10 - API e Endpoints/`, quando aplicavel.
- Roadmap e backlog, se a funcionalidade sair de planejada para implementada.

## Bugs identificados e resolvidos

Registre bugs em:

`12 - Roadmap e Tarefas/Bugs/Bugs Identificados e Resolvidos.md`

Para bugs relevantes, crie nota propria usando:

`00 - Entrada/Templates/Template - Bug.md`

Cada bug deve conter:

- Status.
- Data.
- Area afetada.
- Descricao.
- Impacto.
- Causa raiz.
- Correcao aplicada.
- Como validar.
- Links para notas, codigo ou decisoes relacionadas.

Se um bug revelar uma regra de negocio ausente, atualize:

`09 - Regras de Negocio/Regras de Negocio.md`

Se um bug revelar uma decisao tecnica relevante, atualize:

`13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas.md`

## Roadmap e backlog

Atualize o roadmap quando houver mudanca de fase, prioridade ou direcao do produto:

`12 - Roadmap e Tarefas/Roadmap do Projeto.md`

Atualize o backlog quando surgirem novas ideias, melhorias ou funcionalidades futuras:

`12 - Roadmap e Tarefas/Backlog de Funcionalidades.md`

Nao deixe funcionalidades implementadas apenas no backlog. Quando forem concluidas, registre tambem em:

`12 - Roadmap e Tarefas/Funcionalidades/Funcionalidades Implementadas.md`

## Regras de negocio

Regras permanentes devem ficar em:

`09 - Regras de Negocio/Regras de Negocio.md`

Registre nesta area qualquer regra sobre:

- Clientes.
- Equipamentos.
- Chamados.
- Ordens de servico.
- Produtos e servicos.
- Usuarios e permissoes.
- Monitoramento.
- Privacidade e LGPD.
- Portal do cliente.
- Relatorios.
- Financeiro futuro.

Nao deixe regra de negocio escondida apenas em codigo, tarefa ou bug.

## Modulos do sistema

Documente mudancas funcionais nos modulos em:

`08 - Modulos do Sistema/`

Modulos atuais:

- Clientes.
- Equipamentos.
- Chamados.
- Ordens de Servico.
- Produtos e Servicos.
- Usuarios e Permissoes.
- Monitoramento.
- Relatorios.

Use:

`00 - Entrada/Templates/Template - Modulo.md`

para criar novos modulos.

## Operacao de agentes

Ao iniciar qualquer trabalho no ERP-PAPEZZOSYNC:

1. Ler este `AGENTS.md`.
2. Ler `Dashboard Principal.md`.
3. Identificar as notas afetadas.
4. Consultar a documentacao existente antes de propor resposta.
5. Fazer alteracoes no codigo somente quando o pedido permitir.
6. Atualizar documentacao relevante quando houver mudanca real no projeto.
7. Evitar criar nota nova se uma nota existente puder ser atualizada.
8. Nao apagar nem mover notas sem confirmacao explicita.
9. Antes de qualquer alteracao destrutiva, solicitar confirmacao.

## Quando atualizar o Vault

Atualize o Vault sempre que ocorrer:

- Nova funcionalidade implementada.
- Bug identificado ou resolvido.
- Nova decisao tecnica.
- Alteracao no schema do banco.
- Alteracao em endpoint.
- Alteracao em tela Flutter.
- Alteracao no agente de monitoramento.
- Alteracao em regra de negocio.
- Mudanca de prioridade no roadmap ou backlog.
- Mudanca relevante em instalacao, execucao local ou deploy.

## O que nao fazer

- Nao duplicar documentacao.
- Nao registrar informacoes incertas como fato.
- Nao apagar notas existentes sem autorizacao.
- Nao mover notas existentes sem autorizacao.
- Nao deixar codigo e documentacao divergirem.
- Nao ignorar regras de privacidade do agente.
- Nao responder sobre o projeto sem consultar o Vault quando houver acesso a ele.

## Fonte de verdade

Para contexto do ERP-PAPEZZOSYNC, este Vault deve ser tratado como fonte principal.

O repositorio de codigo mostra o estado implementado.

Quando houver divergencia entre codigo e Vault:

1. Verifique o codigo.
2. Verifique as notas relacionadas.
3. Informe a divergencia.
4. Atualize a documentacao somente se a mudanca for confirmada ou claramente derivada do codigo.


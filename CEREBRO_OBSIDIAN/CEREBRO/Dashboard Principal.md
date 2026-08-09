# Dashboard Principal - ERP-PAPEZZOSYNC

Este vault e a base de conhecimento permanente do projeto ERP-PAPEZZOSYNC.

Atualizado com base no codigo-fonte e documentacao do repositorio de teste em `D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\01_SISTEMA_COMPLETO\ERP-PAPEZZOSYNC`.

Observacao operacional: o sistema de teste/trabalho local fica no volume `D:`. O volume `E:` e usado como HD externo para pacotes de atualizacao que serao enviados ao servidor; nao deve ser tratado como raiz do sistema em desenvolvimento.

## Estado real identificado no projeto

- Backend FastAPI em `backend/app`, com rotas para health, auth, admin, clients, equipments, tickets, monitoring, dashboard, products, pdv, sales e service-orders.
- Banco configurado via SQLAlchemy e PostgreSQL, com `database/schema.sql` contendo o schema inicial e modelos Python contendo a estrutura atualmente mais completa.
- App administrativo Flutter em `admin_app/admin_flutter`, com telas de login, dashboard, clientes, maquinas, OS, vendas, PDV, produtos, operadores PDV e usuarios.
- Agente Python em `agent/papezzosync_agent`, com coleta de CPU, memoria, disco, volumes, temperatura, hostname, sistema operacional, IP, versao do agente e opcionalmente usuario logado.
- Scripts de operacao em `scripts/start-lan.ps1` e `scripts/package-agent.ps1`.
- Documentacao existente em `README.md`, `docs/papezzosync-visao-inicial.md`, `docs/instalar-agente-windows.md` e `docs/teste-rede-local.md`.

## Navegacao principal

- [[01 - Visao Geral/Mapa do Projeto|Mapa do Projeto]]
- [[01 - Visao Geral/Resumo Executivo|Resumo Executivo]]
- [[02 - Produto ERP-PAPEZZOSYNC/MVP|MVP]]
- [[02 - Produto ERP-PAPEZZOSYNC/Roadmap do Produto|Roadmap do Produto]]
- [[03 - Arquitetura/Arquitetura Geral|Arquitetura Geral]]
- [[04 - Backend FastAPI/Backend FastAPI|Backend FastAPI]]
- [[05 - Banco de Dados/Modelo de Dados|Modelo de Dados]]
- [[06 - App Admin Flutter/App Admin Flutter|App Admin Flutter]]
- [[07 - Agente Windows/Agente de Monitoramento|Agente de Monitoramento]]
- [[08 - Modulos do Sistema/Indice de Modulos|Indice de Modulos]]
- [[09 - Regras de Negocio/Regras de Negocio|Regras de Negocio]]
- [[10 - API e Endpoints/Mapa de Endpoints|Mapa de Endpoints]]
- [[11 - Operacao e Deploy/Como Rodar Localmente|Como Rodar Localmente]]
- [[12 - Roadmap e Tarefas/Roadmap do Projeto|Roadmap do Projeto]]
- [[12 - Roadmap e Tarefas/Backlog de Funcionalidades|Backlog de Funcionalidades]]
- [[13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas|Registro de Decisoes Tecnicas]]

## Modulos implementados no codigo

- Autenticacao com JWT.
- Usuarios, perfis e permissoes.
- Clientes.
- Equipamentos.
- Chamados.
- Monitoramento e alertas.
- Dashboard.
- Produtos, pecas, servicos e insumos.
- Ordens de servico com itens, totais e impressao termica.
- Vendas e PDV.
- Operadores de PDV e autorizacoes.

## Fluxo de manutencao

- Antes de criar uma nota nova, consultar este Dashboard, indices e notas relacionadas.
- Reutilizar informacoes ja registradas e criar links internos.
- Registrar decisoes tecnicas relevantes em [[13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas|Registro de Decisoes Tecnicas]].
- Registrar regras de negocio em [[09 - Regras de Negocio/Regras de Negocio|Regras de Negocio]].
- Registrar funcionalidades implementadas em [[12 - Roadmap e Tarefas/Funcionalidades/Funcionalidades Implementadas|Funcionalidades Implementadas]].
- Registrar bugs identificados e resolvidos em [[12 - Roadmap e Tarefas/Bugs/Bugs Identificados e Resolvidos|Bugs Identificados e Resolvidos]].
- Registrar melhorias futuras em [[12 - Roadmap e Tarefas/Backlog de Funcionalidades|Backlog de Funcionalidades]].

## Fontes analisadas

- `README.md`
- `docs/papezzosync-visao-inicial.md`
- `docs/instalar-agente-windows.md`
- `docs/teste-rede-local.md`
- `backend/README.md`
- `backend/app`
- `database/schema.sql`
- `admin_app/README.md`
- `admin_app/admin_flutter`
- `agent/README.md`
- `agent/papezzosync_agent`
- `scripts`

# Resumo Executivo

O PapezzoSync e um ERP/CRM operacional para empresa de informatica. A documentacao inicial define o objetivo de gerenciar clientes, suporte tecnico, chamados, ordens de servico, manutencoes, equipamentos, produtos, contratos, relatorios e monitoramento basico de computadores.

## Estado atual encontrado no codigo

O projeto ja contem uma API FastAPI, um app administrativo Flutter e um agente Python de monitoramento.

## Backend

O backend esta em `backend/app` e usa:

- FastAPI.
- SQLAlchemy.
- PostgreSQL via `psycopg`.
- Pydantic Settings.
- PyJWT.
- CORS configurado para localhost, 127.0.0.1 e IPs `192.168.x.x`.

Modulos de API encontrados:

- Health.
- Autenticacao.
- Administracao de usuarios, perfis e permissoes.
- Clientes.
- Equipamentos.
- Chamados.
- Monitoramento.
- Dashboard.
- Produtos.
- Operadores PDV.
- Vendas.
- Ordens de servico.

## Frontend

O app administrativo Flutter esta em `admin_app/admin_flutter`. Ele usa Material 3, HTTP client e assets de marca. A navegacao e liberada conforme permissoes da sessao.

Telas encontradas:

- Login.
- Dashboard.
- Clientes.
- Maquinas.
- OS.
- Vendas.
- PDV.
- Produtos.
- Operadores PDV.
- Usuarios.

## Agente

O agente esta em `agent/papezzosync_agent` e envia snapshots para `/monitoring/agent/snapshots` usando `X-Agent-Token`.

Dados coletados pelo agente:

- CPU.
- Memoria.
- Disco.
- Volumes de armazenamento.
- Temperatura quando disponivel.
- Hostname.
- Sistema operacional.
- IP local.
- Versao do agente.
- Usuario logado somente se `collect_logged_user` estiver ativo.

## Operacao local documentada

- Backend local: `127.0.0.1:8000`.
- App admin web local: `127.0.0.1:5000`.
- Modo LAN documentado em `docs/teste-rede-local.md` e `scripts/start-lan.ps1`.
- Empacotamento de agente documentado em `docs/instalar-agente-windows.md` e `scripts/package-agent.ps1`.

## Pontos de atencao

- `database/schema.sql` representa o schema inicial, mas os modelos SQLAlchemy e `migrate_local.py` mostram evolucoes posteriores.
- O portal/app do cliente existe como planejamento na documentacao, mas nao foi encontrado codigo de uma interface de cliente separada.
- Nao foi encontrada configuracao formal de Alembic, embora o README do backend mencione Alembic como tecnologia sugerida.

# Arquitetura Geral

## Componentes reais encontrados

### Backend FastAPI

Caminho: `backend/app`.

Responsavel por API REST, autenticacao, permissoes, regras de dominio, persistencia e integracao com agente.

Arquivos centrais:

- `main.py`: cria app FastAPI e configura CORS.
- `api/router.py`: registra routers.
- `core/config.py`: configuracoes via `.env`.
- `core/database.py`: engine, SessionLocal e Base SQLAlchemy.
- `core/security.py`: hash de senha, JWT e token de agente.
- `core/permissions.py`: roles e permissoes.
- `services/access_control.py`: seed e calculo de permissoes.
- `services/monitoring_health.py`: status atual, alertas e historico critico.
- `services/service_order_totals.py`: calculo de totais de OS.

### Banco de dados

Banco configurado para PostgreSQL via `DATABASE_URL`.

`database/schema.sql` contem o schema inicial. Os modelos SQLAlchemy em `backend/app/models` representam a estrutura atual encontrada no codigo, incluindo tabelas adicionais como `products`, `service_orders`, `sales`, `pdv_operators`, `roles`, `permissions`, `role_permissions`, `user_permissions` e `equipment_current_status`.

### App Admin Flutter

Caminho: `admin_app/admin_flutter`.

Responsavel pela interface administrativa. Usa `ApiClient` para acessar a API, guarda sessao no armazenamento do navegador quando disponivel e monta o menu com base nas permissoes do usuario.

### Agente Windows

Caminho: `agent/papezzosync_agent`.

Responsavel por coletar dados de saude/desempenho da maquina e enviar para a API usando token por equipamento.

### Scripts

- `scripts/start-lan.ps1`: inicia backend e app web para acesso na rede local.
- `scripts/package-agent.ps1`: gera `dist/papezzosync-agent.zip`.
- `agent/install-windows.ps1`: instala agente em `%ProgramData%\PapezzoSync\Agent` e cria tarefa agendada.
- `agent/uninstall-windows.ps1`: remove tarefa e pasta de instalacao do agente.

## Fluxo principal

1. Usuario acessa app Flutter.
2. App chama `/auth/login`.
3. Backend valida senha e retorna JWT com permissoes.
4. App exibe telas conforme permissoes.
5. App consome rotas de clientes, equipamentos, produtos, OS, vendas, PDV, usuarios, monitoramento e dashboard.
6. Agente coleta snapshot local e envia para `/monitoring/agent/snapshots` com `X-Agent-Token`.
7. Backend valida token do equipamento, atualiza identidade, status atual, alertas e historico critico.

## Autenticacao e seguranca

- Senhas usam PBKDF2-SHA256 com 600000 iteracoes.
- JWT usa HS256.
- Token de agente e gerado com `secrets.token_urlsafe(32)` e armazenado com hash de senha.
- Rotas administrativas usam dependencias de permissao.
- Agente nao deve coletar tela, arquivos pessoais, senhas, historico de navegacao ou conteudo de documentos, conforme README e docs do agente.

## CORS

Configurado para origens locais e regex permitindo `localhost`, `127.0.0.1` e IPs `192.168.x.x`.

## Pontos de divergencia encontrados

- `database/schema.sql` esta mais simples que os modelos SQLAlchemy atuais.
- README do backend menciona Alembic, mas nao foi encontrada configuracao Alembic no repositorio analisado.
- Portal/app do cliente e planejado, mas nao foi encontrado codigo desse app.

## Decisoes relacionadas

- [[13 - Decisoes Tecnicas/Registro de Decisoes Tecnicas|Registro de Decisoes Tecnicas]]

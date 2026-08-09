# Backend FastAPI

API responsavel por conectar app administrativo, banco de dados e agente de monitoramento.

## Caminho

```text
backend/app
```

## Dependencias encontradas

Arquivo: `backend/requirements.txt`

- `fastapi==0.124.0`
- `uvicorn[standard]==0.38.0`
- `sqlalchemy==2.0.45`
- `psycopg[binary]==3.3.2`
- `pydantic-settings==2.12.0`
- `python-dotenv==1.2.1`
- `email-validator==2.3.0`
- `PyJWT==2.10.1`

## Configuracao

Arquivo: `backend/app/core/config.py`

- `APP_NAME`: nome da API.
- `APP_ENV`: ambiente.
- `DATABASE_URL`: conexao PostgreSQL.
- `SECRET_KEY`: chave JWT.
- `ACCESS_TOKEN_EXPIRE_MINUTES`: padrao 60.
- `CORS_ORIGINS`: origens locais.
- `CORS_ORIGIN_REGEX`: permite localhost, 127.0.0.1 e IPs `192.168.x.x`.

## Rotas registradas

Arquivo: `backend/app/api/router.py`

- `GET /health`
- `/auth`
- `/admin`
- `/clients`
- `/equipments`
- `/tickets`
- `/monitoring`
- `/dashboard`
- `/products`
- `/pdv`
- `/sales`
- `/service-orders`

## Autenticacao

Arquivos: `backend/app/api/routes/auth.py`, `backend/app/core/security.py`.

- `POST /auth/login`: valida email/senha, usuario ativo e retorna JWT com permissoes.
- `GET /auth/me`: retorna usuario atual e permissoes.
- Hash de senha: PBKDF2-SHA256.
- JWT: HS256.

## Permissoes

Arquivos: `backend/app/core/permissions.py`, `backend/app/services/access_control.py`.

Roles encontrados:

- `admin`
- `technician`
- `seller`
- `cashier`
- `client`

Permissoes incluem clientes, equipamentos, chamados, produtos, estoque, vendas, operadores PDV, OS, monitoramento, dashboard, relatorios, financeiro, usuarios e permissoes.

`admin` recebe todas as permissoes. Outros perfis recebem subconjuntos e podem ter overrides em `user_permissions`.

## Modulos implementados

### Clientes

Arquivo: `backend/app/api/routes/clients.py`.

- Criar, listar, obter, atualizar e excluir clientes.
- Listagem pode ser acessada tambem por permissoes relacionadas a vendas, OS e chamados.

### Equipamentos

Arquivo: `backend/app/api/routes/equipments.py`.

- Criar, listar, obter, atualizar e excluir equipamentos.
- Filtro por `client_id`.
- Geracao de token de agente em `POST /equipments/{equipment_id}/agent-token`.

### Chamados

Arquivo: `backend/app/api/routes/tickets.py`.

- Criar, listar, obter, atualizar e excluir chamados.
- Filtros por cliente, equipamento, status e prioridade.
- Valida relacao entre cliente e equipamento.
- Define `closed_at` quando status vira `concluido` ou `cancelado`.

### Monitoramento

Arquivo: `backend/app/api/routes/monitoring.py`.

- `POST /monitoring/snapshots`: envio autenticado por usuario.
- `POST /monitoring/agent/snapshots`: envio por agente com `X-Agent-Token`.
- `GET /monitoring/snapshots`
- `GET /monitoring/current-status`
- `GET /monitoring/alerts`
- Atualiza identidade do equipamento, `last_seen_at`, status atual, alertas e historico critico.

### Dashboard

Arquivo: `backend/app/api/routes/dashboard.py`.

- `GET /dashboard/summary`.
- Conta clientes, equipamentos, online/offline, chamados por status e alertas.
- Online usa janela de 5 minutos.

### Produtos

Arquivo: `backend/app/api/routes/products.py`.

- CRUD de produtos/servicos.
- Filtros por tipo e ativo.
- Busca por codigo interno ou codigo de barras.

### Ordens de servico

Arquivo: `backend/app/api/routes/service_orders.py`.

- CRUD de OS.
- Itens de OS.
- Calculo de totais.
- Impressao termica via socket.
- Codigo automatico `M{id}` quando `number` nao e informado.
- Status `aguardando_aprovacao` exige `waiting_reason`.

### Vendas

Arquivo: `backend/app/api/routes/sales.py`.

- Criar venda.
- Listar e obter vendas.
- Cancelar venda.
- Baixa estoque de produto nao-servico em venda finalizada.
- Cancelamento estorna estoque.
- Numero automatico `V{id}`.

### PDV

Arquivo: `backend/app/api/routes/pdv_operators.py`.

- Listar, criar e atualizar operadores PDV.
- Autorizar acoes por codigo e PIN.
- Acoes: abrir caixa, sangria, cancelar venda e desconto.

### Usuarios e permissoes

Arquivo: `backend/app/api/routes/admin.py`.

- Listar, criar, obter e atualizar usuarios.
- Listar roles.
- Listar permissoes.
- Definir permissao por usuario.

## Comandos principais

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Swagger/OpenAPI:

```text
http://127.0.0.1:8000/docs
```

Criar tabelas:

```powershell
python -m app.db_init
```

Aplicar migracao local:

```powershell
python -m app.migrate_local
```

Criar admin:

```powershell
python -m app.create_admin
```

## Nao determinado

- Nao foi encontrada configuracao Alembic.
- Nao foi encontrada suite de testes automatizados do backend.
- Nao foi verificado se a API inicia sem erro no ambiente atual.

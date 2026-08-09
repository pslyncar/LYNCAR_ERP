# Backend PapezzoSync

API responsavel por conectar o aplicativo administrativo, o banco de dados e o agente de monitoramento.

## Tecnologia sugerida

- Python
- FastAPI
- PostgreSQL
- SQLAlchemy
- Alembic

## Como rodar localmente

Entre na pasta do backend:

```powershell
cd backend
```

Crie o ambiente virtual:

```powershell
python -m venv .venv
```

Ative o ambiente virtual:

```powershell
.\.venv\Scripts\Activate.ps1
```

Instale as dependencias:

```powershell
pip install -r requirements.txt
```

Crie um arquivo `.env` baseado no `.env.example` e coloque a senha do PostgreSQL:

```text
DATABASE_URL=postgresql+psycopg://postgres:sua_senha_aqui@localhost:5432/papezzosync
```

Rode a API:

```powershell
uvicorn app.main:app --reload
```

Depois abra:

```text
http://localhost:8000/docs
```

## Criar tabelas do banco

Depois que o banco `papezzosync` existir no PostgreSQL e o `.env` estiver configurado:

```powershell
python -m app.db_init
```

## Criar usuario administrador

Depois que as tabelas existirem, crie o primeiro admin:

```powershell
python -m app.create_admin
```

Tambem e possivel definir e-mail e senha:

```powershell
python -m app.create_admin --email admin@papezzosync.com.br --password "uma-senha-forte"
```

## Primeiros endpoints planejados

- `GET /health`
- `POST /auth/login`
- `GET /auth/me`
- `GET /admin/users`
- `POST /admin/users`
- `PUT /admin/users/{user_id}`
- `GET /admin/roles`
- `GET /admin/permissions`
- `PUT /admin/users/{user_id}/permissions`
- `POST /clients`
- `GET /clients`
- `GET /clients/{client_id}`
- `PUT /clients/{client_id}`
- `DELETE /clients/{client_id}`
- `POST /equipments`
- `GET /equipments`
- `GET /equipments?client_id={client_id}`
- `GET /equipments/{equipment_id}`
- `PUT /equipments/{equipment_id}`
- `DELETE /equipments/{equipment_id}`
- `POST /tickets`
- `GET /tickets`
- `GET /tickets?client_id={client_id}`
- `GET /tickets?status=aberto`
- `GET /tickets/{ticket_id}`
- `PUT /tickets/{ticket_id}`
- `DELETE /tickets/{ticket_id}`
- `POST /monitoring/snapshots`
- `GET /monitoring/snapshots?equipment_id={equipment_id}`
- `GET /dashboard/summary`
- `POST /products`
- `GET /products`
- `GET /products/{product_id}`
- `PUT /products/{product_id}`
- `DELETE /products/{product_id}`
- `POST /service-orders`
- `GET /service-orders`
- `GET /service-orders/{service_order_id}`
- `PUT /service-orders/{service_order_id}`
- `POST /service-orders/{service_order_id}/items`
- `DELETE /service-orders/{service_order_id}`

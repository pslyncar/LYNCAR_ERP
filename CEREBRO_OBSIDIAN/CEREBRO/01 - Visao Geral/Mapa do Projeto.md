# Mapa do Projeto

O ERP-PAPEZZOSYNC e uma plataforma interna para empresa de informatica, com foco em ERP/CRM operacional.

## Estrutura real do repositorio

```text
ERP-PAPEZZOSYNC/
  README.md
  backend/
    app/
      api/
      core/
      models/
      schemas/
      services/
      main.py
      db_init.py
      migrate_local.py
      create_admin.py
    requirements.txt
    .env.example
    README.md
  database/
    schema.sql
  admin_app/
    README.md
    admin_flutter/
      lib/
        screens/
        models/
        services/
        widgets/
        utils/
      assets/brand/
      pubspec.yaml
  agent/
    papezzosync_agent/
      collector.py
      config.py
      sender.py
      main.py
      advisor.py
    vendor/LibreHardwareMonitor/
    install-windows.ps1
    uninstall-windows.ps1
    requirements.txt
    README.md
  docs/
  scripts/
```

## Areas principais

- Produto: [[02 - Produto ERP-PAPEZZOSYNC/MVP|MVP]], roadmap e funcionalidades futuras.
- Arquitetura: [[03 - Arquitetura/Arquitetura Geral|Arquitetura Geral]].
- Backend: [[04 - Backend FastAPI/Backend FastAPI|Backend FastAPI]].
- Banco de dados: [[05 - Banco de Dados/Modelo de Dados|Modelo de Dados]].
- Interface administrativa: [[06 - App Admin Flutter/App Admin Flutter|App Admin Flutter]].
- Agente: [[07 - Agente Windows/Agente de Monitoramento|Agente de Monitoramento]].
- Modulos: [[08 - Modulos do Sistema/Indice de Modulos|Indice de Modulos]].
- Regras: [[09 - Regras de Negocio/Regras de Negocio|Regras de Negocio]].
- Operacao: [[11 - Operacao e Deploy/Como Rodar Localmente|Como Rodar Localmente]].

## Componentes encontrados

- `backend/`: API em Python com FastAPI, SQLAlchemy, Pydantic, JWT e PostgreSQL.
- `database/`: `schema.sql` com schema inicial do MVP.
- `admin_app/admin_flutter/`: app administrativo em Flutter/Dart.
- `agent/`: agente Python de monitoramento e scripts de instalacao Windows.
- `agent/vendor/LibreHardwareMonitor/`: binarios do LibreHardwareMonitor presentes no repositorio.
- `docs/`: visao inicial, instalacao do agente e teste em rede local.
- `scripts/`: automacao para iniciar em LAN e empacotar agente.

## Rotas principais do backend

- `/health`
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

## Telas do app Flutter

- Login.
- Dashboard.
- Clientes.
- Maquinas/equipamentos.
- Ordens de servico.
- Vendas.
- PDV.
- Produtos.
- Operadores PDV.
- Usuarios.

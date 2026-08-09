# PapezzoSync

Sistema ERP/CRM para gerenciamento de suporte tecnico, clientes, chamados, ordens de servico, manutencoes, equipamentos, produtos e monitoramento basico de computadores.

## Ideia principal

A PapezzoSync sera uma plataforma interna completa para empresa de informatica, com login e modulos operacionais como:

- Dashboard administrativo
- Cadastro de clientes
- Cadastro de computadores e equipamentos
- Sistema de chamados
- Ordens de servico
- Registro de manutencoes
- Cadastro de produtos, pecas e servicos
- Monitoramento basico de desempenho das maquinas
- Relatorios de atendimento e manutencao
- Futuro controle financeiro e contratos

## Interfaces planejadas

O projeto deve evoluir com duas interfaces Flutter:

- App administrativo para admin, tecnicos, vendedores e colaboradores.
- Portal/app do cliente para abrir chamados, solicitar manutencao e acompanhar maquinas/OS.

## Perfis iniciais

- Admin: acesso total e controle de usuarios/permissoes.
- Tecnico: chamados, equipamentos, OS, manutencoes e monitoramento.
- Vendedor: clientes, produtos, estoque, orcamentos e vendas futuras.
- Cliente: acesso apenas aos seus proprios dados, maquinas, chamados e OS.

O sistema deve permitir liberar ou bloquear permissoes especificas por usuario, alem do perfil principal.

## Tecnologias planejadas

- Backend/API: Python com FastAPI
- Banco de dados: PostgreSQL
- Interface administrativa: Flutter/Dart
- Agente de monitoramento: Python

## Ordem de desenvolvimento

1. Criar backend/API.
2. Criar banco de dados.
3. Implementar clientes, equipamentos e chamados.
4. Criar agente de monitoramento.
5. Criar dashboard.
6. Criar login/autenticacao.
7. Criar interface Flutter.
8. Adicionar produtos, OS e manutencoes.
9. Adicionar relatorios e financeiro futuro.

## Documentacao

A visao inicial completa esta em:

- `docs/papezzosync-visao-inicial.md`

## Rodar localmente

Backend:

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

App administrativo web:

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\admin_app\admin_flutter
C:\Users\vpape\Documents\DevTools\flutter\bin\flutter.bat run -d web-server --web-hostname 127.0.0.1 --web-port 5000
```

URLs:

- API: `http://127.0.0.1:8000/docs`
- App admin: `http://127.0.0.1:5000`

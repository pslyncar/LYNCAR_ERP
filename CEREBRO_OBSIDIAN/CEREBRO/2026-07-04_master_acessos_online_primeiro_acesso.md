# 2026-07-04 - Master: acessos online e primeiro acesso

Foi criado um acompanhamento separado no Master para ver clientes/empresas online e status de primeiro acesso.

## Decisao

- O ERP continua sendo Flutter/Dart no frontend.
- O backend continua Python/FastAPI.
- A presenca online fica no banco master, nao nos bancos dos clientes.
- Cada usuario logado envia heartbeat periodico para `/auth/heartbeat`.
- O Master consulta `/master/access-status`.
- A empresa e considerada online quando existe heartbeat nos ultimos 3 minutos.

## Primeiro acesso

O sistema ja possuia:

- `users.must_change_password`
- `users.password_changed_at`

A tela do Master usa esses campos para exibir:

- usuarios ativos;
- senhas provisorias pendentes;
- senhas ja alteradas;
- se a empresa ja fez primeiro acesso.

## Arquivos principais

- `backend/app/models/company_presence.py`
- `backend/app/services/company_presence.py`
- `backend/app/api/routes/master_access.py`
- `backend/app/api/routes/auth.py`
- `admin_app/admin_flutter/lib/screens/master_access_screen.dart`
- `admin_app/admin_flutter/lib/models/master_access_status.dart`
- `admin_app/admin_flutter/lib/app.dart`
- `admin_app/admin_flutter/lib/screens/app_shell.dart`

## Pacote

Atualizacao criada em:

`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_MASTER_ACESSOS_ONLINE_2026-07-04`

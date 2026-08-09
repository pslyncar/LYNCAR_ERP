# 2026-06-28 - Renovacao de sessao ERP

## Problema

Cliente usando o ERP/site normalmente era desconectada e voltava para a tela de login.

## Causa

O token JWT do backend expira em 60 minutos. O frontend chamava `/auth/me`, mas esse endpoint nao renovava token; apenas retornava os dados do usuario. Assim, mesmo com uso ativo, o token vencia e o timer do frontend mandava o usuario para login.

O timeout de inatividade do site tambem estava em 30 minutos, agressivo para rotinas longas.

## Correcao

- Criado `POST /auth/refresh` no backend.
- `ApiClient.refreshSession()` agora troca o token antigo por um novo.
- O ERP renova automaticamente quando o token esta perto de vencer.
- Falha temporaria de internet/API durante refresh nao derruba usuario antes do vencimento.
- Inatividade do ERP/site ajustada para 8 horas.

## Arquivos

- `backend/app/api/routes/auth.py`
- `admin_app/admin_flutter/lib/app.dart`
- `admin_app/admin_flutter/lib/models/session.dart`
- `admin_app/admin_flutter/lib/services/api_client.dart`

## Entrega

- `E:\ENTREGAS_CLIENTES\ATUALIZACAO_URGENTE_2026-06-28_SESSAO_NAO_DESCONECTAR`
- `E:\ENTREGAS_CLIENTES\ATUALIZACAO_URGENTE_2026-06-28_SESSAO_NAO_DESCONECTAR.zip`

## Testes

- `python -m compileall backend/app/api/routes/auth.py`
- `dart format`
- `flutter analyze`
- `flutter build web --release`

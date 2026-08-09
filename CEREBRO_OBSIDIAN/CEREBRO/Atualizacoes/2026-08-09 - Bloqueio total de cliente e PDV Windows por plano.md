# 2026-08-09 - Bloqueio total de cliente e PDV Windows por plano

## Decisao

Quando uma empresa cliente for bloqueada no master (`active=false` ou `status` diferente de `active`), o backend deve bloquear todos os acessos do tenant:

- login novo;
- refresh de token;
- rotas autenticadas do ERP web;
- usuarios criados pelo cliente;
- PDV Windows;
- ativacao de novo terminal PDV Windows.

Quando o modulo `pdv_windows` sair do plano ou da liberacao especifica da empresa, o PDV Windows deve parar de funcionar na autorizacao do servidor. O terminal nao deve ser marcado permanentemente como bloqueado so por mudanca de plano, porque a liberacao precisa ser reversivel ao reativar o modulo.

## Implementacao

- `backend/app/core/database.py`: tokens de tenant que apontam para empresa bloqueada/inativa agora recebem HTTP 403 com mensagem clara, em vez de estourar erro bruto ao abrir o banco.
- `backend/app/api/dependencies.py`: dependencia central valida a empresa em toda rota autenticada de tenant e bloqueia token de PDV Windows se `pdv_windows` nao estiver contratado.
- `backend/app/api/routes/auth.py`: login/refresh/leitura de sessao e ativacao de terminal validam empresa ativa e modulo `pdv_windows`.
- `admin_app/admin_flutter/lib/main_pdv.dart`: quando o servidor retorna 403 no refresh do PDV Windows, o app mostra a mensagem do servidor, por exemplo plano nao liberado ou empresa bloqueada.

## Regra operacional

O master continua acessivel para a Lyncar mesmo quando um cliente e bloqueado, para permitir desbloqueio, ajuste de plano e manutencao.

Para efetivar em producao, publicar o backend atualizado. A melhoria de mensagem no aplicativo Windows exige novo build/distribuicao do PDV Windows, mas o bloqueio em si ja e imposto pelo servidor.

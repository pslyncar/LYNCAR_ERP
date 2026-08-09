# Atualizacao ERP - Primeiro login senha e pro-rata - 2026-06-30

## Objetivo
Implementada rotina para exigir troca de senha no primeiro login e permitir edicao de cobrancas no Master, incluindo calculo de pro-rata.

## Primeiro login
- Novos usuarios criados no ERP recebem `must_change_password = true`.
- Primeiro admin criado no provisionamento da empresa tambem recebe `must_change_password = true`.
- Login retorna `must_change_password` no token response.
- Frontend abre dialogo obrigatorio para criar senha definitiva antes de entrar.
- Endpoint novo: `POST /auth/change-password`.
- Ao trocar senha: grava hash novo, `must_change_password = false` e `password_changed_at`.
- Reset/troca de senha pelo Master volta a exigir troca no proximo login.

## Master > Cobrancas
- Cobrancas pendentes/canceladas podem ser editadas.
- Cobrancas pagas ficam travadas.
- Campos editaveis: vencimento, valor, forma de pagamento, status e observacoes.
- Alteracao financeira limpa Pix/Mercado Pago antigo quando pendente, evitando cobranca com valor antigo.

## Pro-rata
Formula: `mensalidade * dias_ate_vencimento / dias_do_mes_atual`.
Exemplo 30/06/2026 com vencimento 10/07/2026 e mensalidade 59,90:
`59,90 * 10 / 30 = 19,97`.

## Entrega em E:
- Pasta: `E:\ENTREGAS_CLIENTES\ATUALIZACAO_ERP_SITE_2026-06-30_LOGIN_SENHA_PRORATA`
- Zip: `E:\ENTREGAS_CLIENTES\ATUALIZACAO_ERP_SITE_2026-06-30_LOGIN_SENHA_PRORATA.zip`

## Validacao
- Python py_compile: OK.
- Migracoes master/local: OK.
- flutter analyze: OK.
- flutter build web --release: OK.

## Observacao
Nao altera Motor Fiscal.

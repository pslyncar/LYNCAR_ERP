# Dia comercial do PDV e separacao de responsabilidades

Implementado em 01/08/2026 no codigo-fonte canonico `C:\erp_build`.

## Regra funcional

- O cliente configura o horario de corte do dia comercial na tela `Terminais PDV`.
- Horario padrao: 03:00 (`180` minutos apos meia-noite).
- O master pode alterar esse horario apenas como recurso de suporte ao cliente.
- O master nao consulta nem exibe vendas, quantidade de vendas, valores vendidos ou total da sessao do cliente.
- O cliente continua vendo vendas e valores dos seus proprios terminais.
- Quando uma sessao aberta atravessa o corte, o terminal do cliente mostra `Atravessou o dia comercial`.
- O master tambem ve esse estado para diagnostico, sem acesso aos valores financeiros.
- Ao fechar o caixa, o fechamento grava permanentemente:
  - `business_date`
  - `crossed_business_day`
  - `business_day_cutoff_minutes`
- A tela de conferencia/tesouraria mostra o alerta no registro fechado, mesmo depois que a sessao deixou de estar aberta.

## Codigo

- Regra central: `C:\erp_build\backend\app\services\business_day.py`
- Configuracao da empresa: `Company.business_day_cutoff_minutes`
- Snapshot do fechamento: modelo e schema `CashClosing`
- Rotas do cliente: `/pdv/business-day-settings`
- Fallback do master: `/master/pdv/business-day-settings`
- Tela cliente: `pdv_terminals_screen.dart`
- Tela master: `master_pdv_terminals_screen.dart`
- Conferencia: `cash_closings_screen.dart`

## Validacao

- Teste do corte de 03:00 aprovado.
- Backend compilado com `compileall`.
- `flutter analyze`: sem problemas.
- Build web release gerado e versionado como `20260801085723`.
- Fontes alteradas validadas como UTF-8 sem mojibake.

## Backup anterior

`C:\LYNCAR_BACKUPS\BACKUP_DIA_COMERCIAL_20260801-083140`

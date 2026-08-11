# 2026-08-11 - Baixa financeira comparando centavos

## Problema

Na tela Financeiro, a baixa de contas a receber podia ser bloqueada com a mensagem `Valor maior que o saldo em aberto.` mesmo quando o usuario digitava exatamente o valor exibido na tela.

Exemplo observado pela cliente:

- saldo exibido: `R$ 259,56`;
- valor digitado: `259,56`;
- o sistema recusava a baixa.

A causa era diferenca invisivel de casas decimais/precisao: a interface formatava o saldo em centavos, mas a validacao comparava o numero bruto.

## Ajuste

- `admin_app/admin_flutter/lib/screens/finance_screen.dart`
  - A validacao da baixa agora compara valores convertidos para centavos arredondados.
  - Aplicado em:
    - recebimento geral por cliente;
    - baixa individual de conta a receber;
    - baixa de conta a pagar.

- `backend/app/api/routes/receivables.py`
  - A API arredonda valores monetarios para 2 casas decimais antes de comparar, gravar pagamento e atualizar saldo.
  - Aplicado na baixa individual e na baixa geral por cliente.

- `backend/app/api/routes/payables.py`
  - Mesmo criterio de arredondamento monetario aplicado em contas a pagar.

## Resultado esperado

O valor aceito para baixa passa a ser o mesmo valor financeiro exibido ao usuario em tela. Se a tela mostra `R$ 259,56`, digitar `259,56` deve quitar corretamente, sem rejeicao por fracao decimal invisivel.

## Validacao local

- MCP Dart/Flutter `analyze_files` em `lib/screens/finance_screen.dart`: sem erros.
- `flutter analyze lib/screens/finance_screen.dart`: sem issues.
- `python -m py_compile backend/app/api/routes/receivables.py backend/app/api/routes/payables.py`: OK.
- `git diff --check`: OK.

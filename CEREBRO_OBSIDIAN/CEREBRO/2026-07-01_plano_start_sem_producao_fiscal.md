# 2026-07-01 - Plano Start sem Producao e Fiscal

## Decisao

O plano Start nao deve liberar nem vir com selecionado:

- Producao
- Contratos variaveis
- Fiscal

Esses modulos passam a ser Pro ou superior.

## Alteracoes

- `backend/app/services/company_modules.py`
  - `production`, `service_contracts` e `fiscal` exigem plano `pro`.

- `admin_app/admin_flutter/lib/screens/companies_screen.dart`
  - No modal do Master, o plano Start remove e bloqueia os chips desses modulos.
  - Ao trocar plano ou segmento, os modulos nao permitidos pelo plano sao removidos.

- Mantida a regra anterior:
  - `Notas fiscais` e `Configuracoes > Fiscal` aparecem somente com `canUseFiscal`.

## Entrega

- Pasta:
  - `E:\ENTREGAS_CLIENTES\ATUALIZACAO_ERP_SITE_2026-07-01_START_SEM_PRODUCAO_FISCAL`
- Zip:
  - `E:\ENTREGAS_CLIENTES\ERP_START_SEM_PRODUCAO_FISCAL_2026-07-01.zip`

## Validacao

- `python -m py_compile`: OK
- `flutter analyze`: OK
- `flutter build web --release`: OK


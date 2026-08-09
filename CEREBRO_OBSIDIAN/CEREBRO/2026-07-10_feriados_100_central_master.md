# 2026-07-10 - Feriados 100% centralizados no Master

Decisao tecnica: feriados oficiais sao dados globais do sistema, nao dados de cada tenant.

## O que mudou

- A base operacional de feriados fica no Master:
  - `master_holidays`
  - `master_holiday_syncs`
- `backend/app/services/holidays.py` nao espelha mais feriados para a tabela local `holidays` do cliente.
- `ensure_holidays_for_period(...)` foi mantida por compatibilidade, mas agora so pre-aquece o cache central.
- `backend/app/api/routes/service_contracts.py` passou a usar `is_holiday(...)` do Master para decidir se um dia de contrato e feriado.
- `backend/app/services/master_holidays.py` ganhou `is_holiday(...)`, separada de `is_non_business_day(...)`, porque contratos precisam diferenciar feriado de sabado/domingo.

## Compatibilidade

- Atualizacao final: a tabela local `holidays` foi removida do codigo tenant.
- Removidos model `Holiday`, schemas `HolidayPayload`/`HolidayRead` e rotas `/service-contracts/holidays`.
- `migrate_local/create_all` nao deve mais recriar a tabela porque o model nao existe mais.
- A tabela fisica antiga pode ser dropada dos bancos dos clientes depois do deploy e teste desta versao.
- Nunca dropar `master_holidays`/`master_holiday_syncs`, pois essas sao as tabelas centrais corretas.

## Validacao local

- 09/07/2026 SP: feriado verdadeiro; proximo dia util 10/07/2026.
- 17/06/2026 Leme/SP: feriado municipal verdadeiro; proximo dia util 18/06/2026.
- 10/07/2026 SP: nao e feriado.

## Entrega

Pacote: `ATUALIZACAO_FERIADOS_100_CENTRAL_MASTER_2026-07-10`.
Pacote final sem holidays tenant: `ATUALIZACAO_FERIADOS_MASTER_SEM_HOLIDAYS_TENANT_2026-07-10`.

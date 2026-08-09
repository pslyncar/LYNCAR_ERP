# 2026-07-08 - Feriados centralizados no Master e vencimento em dia util

Implementado cache central de feriados no banco Master para evitar consulta repetida em APIs externas e evitar duplicar dados iguais em cada banco de cliente.

## Decisao

- Feriados oficiais/cacheados ficam em tabelas centrais do Master:
  - `master_holidays`
  - `master_holiday_syncs`
- A cobranca mensal das empresas do Master usa essa base para ajustar vencimento para o proximo dia util.
- Atualizacao 2026-07-10: as rotinas automaticas dos tenants deixaram de espelhar feriados para a tabela local `holidays`. `app.services.holidays.ensure_holidays_for_period` agora apenas pre-aquece o cache central do Master, e os contratos consultam `master_holidays` diretamente. A tabela local `holidays` pode continuar existindo por compatibilidade/tela manual, mas nao deve mais receber carga automatica.

## Regra

- Se vencimento cair em sabado, domingo ou feriado conhecido, ajustar para o proximo dia util.
- Se cair em dia util, manter.
- A consulta de feriados nacionais e feita por ano inteiro via BrasilAPI e salva no Master.
- Uma sincronizacao bem-sucedida nao e repetida por 30 dias para o mesmo ano/escopo.
- Quando outro ano for necessario, o sistema consulta aquele ano e salva.

## Fontes

- Nacional: BrasilAPI `/api/feriados/v1/{ano}`.
- Estadual: FeriadosAPI `/api/v1/feriados/estado/{UF}?ano={ano}` quando `FERIADOS_API_TOKEN` estiver configurado.
- Municipal: FeriadosAPI `/api/v1/feriados/cidade/{codigo_ibge}?ano={ano}` quando `FERIADOS_API_TOKEN` estiver configurado.
- Base interna estadual inicial:
  - SP 09/07 - Revolucao Constitucionalista de 1932.

## Arquivos

- `backend/app/models/master_holiday.py`
- `backend/app/services/master_holidays.py`
- `backend/app/services/company_billing.py`
- `backend/app/services/holidays.py`
- `backend/app/migrate_master.py`

## Testes locais

- `python -m py_compile` dos arquivos alterados: OK.
- `python -m app.migrate_master`: OK.
- 09/07/2026 SP ajusta para 10/07/2026.
- 10/07/2026 permanece 10/07/2026.
- 11/07/2026 sabado ajusta para 13/07/2026.
- Token novo testado em 08/07/2026:
  - Nacionais 2026: HTTP 200.
  - Estado SP 2026: HTTP 200.
  - Cidade Sao Paulo/SP 2026: HTTP 200.
  - Cidade Leme/SP 2026: HTTP 403 Forbidden.
  - Conclusao: token funciona; o bloqueio ocorre especificamente no endpoint/cidade Leme ou permissao de municipio.

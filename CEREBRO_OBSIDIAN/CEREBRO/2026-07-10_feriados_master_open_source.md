# 2026-07-10 - Feriados Master com base open source

Criada evolucao da rotina de feriados centralizada no Master para usar fonte open source gratuita.

## Decisao

- Base central continua no Master:
  - `master_holidays`
  - `master_holiday_syncs`
- Adicionada coluna `city_code` para guardar codigo IBGE.
- A cobranca do Master usa `city`, `state` e `city_code` da empresa para ajustar vencimento ao proximo dia util.
- Atualizacao posterior no mesmo dia: os modulos automaticos dos tenants nao leem mais `holidays` local para decidir feriado. `service_contracts.py` consulta o Master diretamente por `is_holiday(...)`. O servico `holidays.py` apenas pre-aquece a base central e nao grava mais feriados nos bancos dos clientes.

## Fontes

1. BrasilAPI para nacionais.
2. FeriadosAPI para estadual/municipal quando token e cota permitirem.
3. Repositorio open source MIT `joaopbini/feriados-brasil` para estadual/municipal via JSON:
   - `dados/feriados/estadual/json/{ano}.json`
   - `dados/feriados/municipal/json/{ano}.json`
   - `dados/localizacao/municipios/municipios.json`
   - `dados/localizacao/estados/estados.json`

## Resultado de teste

- 2026 importado com sucesso da base open source.
- Total ativo 2026 no Master local apos importacao: 8597.
- Leme/SP (`3526704`) recebeu:
  - 03/04/2026 - Sexta-feira da Paixao
  - 04/06/2026 - Corpus Christi
  - 17/06/2026 - Dia de Sao Manoel
  - 29/08/2026 - Dia da cidade
- 09/07/2026 SP ajusta para 10/07/2026.
- 17/06/2026 Leme/SP ajusta para 18/06/2026.

## Observacao importante

Ano futuro depende da disponibilidade da fonte:

- 2026 existe no open source.
- 2027 retornou 404 no open source durante teste local.
- Para ano sem arquivo open source, nacional/estadual seguem via API, municipal depende da FeriadosAPI/cota.

## Backup

Backup antes da alteracao:

`outputs/BACKUP_ANTES_FERIADOS_OPEN_SOURCE_2026-07-10_09-38-03.zip`

## Pacote

Atualizacao final:

`outputs/ATUALIZACAO_FERIADOS_CENTRAL_MASTER_COBRANCAS_2026-07-10`

Copiar para `F:` quando disponivel; nao usar `E:` para esta entrega.

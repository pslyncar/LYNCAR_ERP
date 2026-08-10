# 2026-08-09 - Ajuste manual de mensalidade do mes

## Problema

Na tela master de cobrancas, uma mensalidade gerada automaticamente podia ser editada para um valor menor/maior apenas naquele mes. Porem, ao recarregar a lista, a rotina automatica de mensalidades identificava a observacao padrao da cobranca e recalculava o valor a partir do cadastro da empresa.

## Ajuste

Quando uma cobranca pendente gerada automaticamente recebe alteracao financeira manual (`amount`, `due_date` ou `payment_method`), o backend adiciona a observacao:

`Ajuste manual aplicado nesta mensalidade.`

Com isso a cobranca deixa de ser tratada como automatica recalculavel e o valor editado fica preservado apenas naquela mensalidade.

## Regra

Alterar uma cobranca ja gerada nao muda o valor mensal cadastrado na empresa. O cadastro continua sendo a base para os proximos meses.

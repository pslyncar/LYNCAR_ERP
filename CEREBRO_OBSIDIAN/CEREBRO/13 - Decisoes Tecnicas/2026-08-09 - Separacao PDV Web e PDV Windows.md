# 2026-08-09 - Separacao PDV Web e PDV Windows

## Decisao

PDV Web e PDV Windows sao produtos/acessos diferentes.

## Regra

- `pdv` = PDV Web / botao de vender no sistema web.
- `pdv_windows` = aplicativo Windows do PDV, terminais, ativacao de terminal, operadores/fiscais do caixa e logo da tela OBRIGADO.

## Planos

- PDV Web pode existir em todos os planos.
- PDV Windows deve ser liberado separadamente por plano ou por excecao manual no cadastro da empresa.
- Nao existe plano minimo fixo no codigo para PDV Windows. Quem decide se Start, Pro, Business ou Enterprise terao PDV Windows e a Lyncar no Master.

## Bloqueios obrigatorios

- Sem `pdv_windows`, o cliente nao deve ver Terminais, Op. PDV ou Logo do PDV Windows.
- Sem `pdv_windows`, o Master/backend nao deve gerar ou ativar terminal Windows para aquela empresa.
- A foto da tela OBRIGADO pertence ao PDV Windows, nao ao PDV Web.

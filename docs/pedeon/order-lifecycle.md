# Ciclo de vida de pedido e pagamento

## Pedido

```text
awaiting_payment
  -> awaiting_acceptance
  -> accepted
  -> in_preparation
  -> ready
  -> out_for_delivery
  -> completed
```

Cancelamento pode ocorrer enquanto a operacao permitir. Pedido aguardando pode
expirar. Retirada vai de `ready` diretamente para `completed`.

## Pagamento

```text
pending
  -> confirmed
  -> partially_refunded
  -> refunded
```

Para Pix manual:

```text
pending
  -> awaiting_manual_confirmation
  -> confirmed | failed | expired
```

Estados de pedido e pagamento permanecem separados. Um pagamento confirmado
nao significa automaticamente que a cozinha recebeu o pedido; a politica de
aceite da empresa decide a transicao seguinte.

## Producao, expedicao e canais

Ao aceitar, a politica padrao cria tarefas por estacao e trabalhos de impressao
idempotentes e avanca para `in_preparation`; o operador nao confirma duas vezes
a mesma decisao. A cozinha marca `ready`. Em entrega, a captura por entregador
pode avancar para `out_for_delivery`, e o botao Entregue para `completed`.

Cada transicao e cada ticket carregam `source_channel` e
`external_order_id`. Assim PedeOn, mesa/local, PDV, iFood, 99Food e futuros
adaptadores permanecem identificaveis em toda a operacao.

## Estoque e venda

1. Checkout pode criar reserva temporaria com expiracao.
2. Pagamento confirmado ou aceite converte a reserva em compromisso efetivo.
3. Cancelamento ou expiracao libera a reserva.
4. Conclusao converte exatamente uma vez o pedido em venda.
5. A venda consome a reserva sem realizar uma segunda baixa.
6. Financeiro e fiscal recebem o identificador da venda criada.

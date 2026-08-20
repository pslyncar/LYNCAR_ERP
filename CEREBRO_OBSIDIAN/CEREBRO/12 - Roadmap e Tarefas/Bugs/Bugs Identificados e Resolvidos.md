# Bugs Identificados e Resolvidos

Registrar bugs confirmados, impacto, causa, correcao e data de resolucao.

## Indice

- [[#2026-06-08 - PDV indicava falha ao finalizar venda com estoque negativo]]
- [[#2026-06-08 - Atalhos do PDV podiam abrir modais duplicados]]

## 2026-06-08 - PDV indicava falha ao finalizar venda com estoque negativo

Status: resolvido.

Area afetada: PDV, Vendas, Estoque, Backend FastAPI e App Admin Flutter.

Descricao: ao finalizar uma venda no PDV com produto sem saldo suficiente, a venda podia ser gravada, mas a tela exibia falha ao finalizar.

Impacto: o operador poderia acreditar que a venda nao foi salva e tentar finalizar novamente, gerando risco de duplicidade operacional.

Causa raiz: a regra de negocio passou a permitir estoque negativo em Vendas/PDV, mas o schema de produto ainda validava `stock_quantity >= 0`. Depois da venda, o PDV recarregava a lista de produtos e o endpoint de produtos falhava ao serializar produto com saldo negativo.

Correcao aplicada: o schema de produto agora permite retornar e atualizar saldo negativo quando a operacao gerar esse estado. O PDV tambem foi ajustado para nao tratar falha de recarregamento da tela como falha da venda ja finalizada.

Como validar: finalizar venda de produto com estoque zerado/negativo, confirmar que a venda e criada, que o produto aparece com saldo negativo em Estoque e que `/products?active=true` responde normalmente.

## 2026-06-08 - Atalhos do PDV podiam abrir modais duplicados

Status: resolvido.

Area afetada: PDV, atalhos de teclado e App Admin Flutter.

Descricao: ao pressionar repetidamente atalhos como `F9` para cancelar venda, o PDV podia abrir mais de um modal de autorizacao/cancelamento, deixando dialogs empilhados.

Impacto: o operador precisava fechar um modal e depois fechar outro igual que ficou atras, causando confusao no caixa.

Causa raiz: o PDV tinha dois caminhos de atalhos, `HardwareKeyboard` global e `Shortcuts/Actions`, mas a trava existente cobria apenas o dialogo de pagamento. Acoes sensiveis como desconto, cancelamento de item, cancelamento de venda, sangria e cancelamento de venda do historico nao tinham uma trava compartilhada.

Correcao aplicada: o PDV passou a usar travas de dialogo/acao sensivel para bloquear novos atalhos enquanto pagamento, autorizacao fiscal, salvamento ou outra acao sensivel estiver aberta. Os callbacks de `Shortcuts/Actions` tambem passaram a respeitar a mesma regra.

Como validar: abrir o PDV, adicionar item, pressionar `F9` varias vezes rapidamente e confirmar que apenas um modal de autorizacao aparece. Repetir com `F4`, `F5` e `F6` para confirmar que desconto, cancelamento de item e pagamento tambem nao duplicam dialogs.

## 2026-08-20 - Edicao fiscal podia inverter estoque negativo

Status: resolvido.

Area afetada: Estoque, cadastro de produtos, fiscal, Backend FastAPI e App Admin Flutter.

Descricao: ao salvar um produto com saldo negativo depois de preencher dados fiscais, o saldo podia reaparecer positivo.

Causa raiz: o formatador/interpretador de numero removia o sinal negativo e o formulario enviava `stock_quantity` em toda edicao do cadastro.

Correcao aplicada: saldo ficou bloqueado no cadastro existente; a API de edicao recusa `stock_quantity`; foi criado ajuste rastreavel com motivo e observacao. O formatador numerico passou a preservar sinal negativo no fluxo de ajuste.

Como validar: editar NCM ou qualquer dado fiscal de produto com saldo negativo e confirmar que o saldo nao muda. Depois, usar **Ajustar estoque**, informar saldo negativo e observacao, e confirmar o novo movimento no historico.

## Template

Usar [[00 - Entrada/Templates/Template - Bug|Template - Bug]] para novos registros.

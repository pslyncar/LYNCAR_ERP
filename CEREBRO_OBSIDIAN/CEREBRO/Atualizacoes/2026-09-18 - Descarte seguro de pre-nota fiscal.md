# Descarte seguro de pré-nota fiscal

## Entrega

- NF-e e NFC-e preparadas podem ser descartadas somente antes de receber número, chave de acesso, XML, protocolo ou qualquer transmissão registrada.
- O descarte remove a pré-nota e seus itens/vínculos fiscais, preservando integralmente vendas, contas a receber e estoque.
- Uma pré-nota criada a partir do Financeiro com várias vendas deixa de aparecer como `preparada` em todas as vendas vinculadas após o descarte; as mesmas vendas voltam a poder compor uma nova NF-e agrupada.
- A tela fiscal expõe a ação **Descartar rascunho** apenas para os estados internos sem numeração: preparada, aguardando A1 ou aguardando configuração.

## Regra de segurança da numeração

- O número fiscal continua sendo reservado apenas no envio à SEFAZ, sob bloqueio da configuração fiscal da empresa/série.
- Nota com número reservado, assinatura, transmissão, rejeição, contingência, autorização ou cancelamento não pode ser descartada nem ter o número reutilizado.
- Esses casos devem ser corrigidos e retransmitidos com o mesmo número, cancelados na SEFAZ ou inutilizados quando houver quebra efetiva de sequência.

## Validação

- `pytest tests/test_fiscal_draft_discard.py tests/test_fiscal_number_reservation.py tests/test_fiscal_queue.py -q`: 9 aprovados.
- Análise Flutter sem erros novos; permanecem dois avisos antigos de estilo em `api_client.dart` (linhas 430 e 450), fora desta alteração.

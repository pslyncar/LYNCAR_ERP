# Motor fiscal: CFOP orientado por operação

## Problema observado

A NF-e 18 de homologação foi rejeitada pela SEFAZ com o código 518. O item
`Açúcar Refinado 1kg TESTE` levou o CFOP `1102` (entrada) porque o cadastro do
produto tinha esse valor no campo de venda. O resolvedor anterior aceitava
qualquer CFOP de quatro dígitos e deixava o cadastro do produto superar a
regra/padrão de saída.

## Decisão

O CFOP não é atributo absoluto do produto. A emissão deve considerar a família
da operação, direção, UF de origem/destino e o modelo fiscal. A regra fiscal
de saída aplicável tem prioridade sobre a exceção do produto. O CFOP do produto
continua sendo fallback quando não há regra, mas passa por guarda obrigatória.

## Proteções adicionadas

- A natureza textual atual identifica a família `venda`, `devolução`,
  `transferência`, `bonificação` ou `remessa` para seleção de regras.
- A regra fiscal aplicável decide o CFOP antes do cadastro do produto.
- O pre-flight bloqueia antes de reservar número/chave:
  - CFOP `1/2/3xxx` em documento de saída;
  - CFOP `5/6/7xxx` em documento de entrada;
  - CFOP interno, interestadual ou exterior incompatível com o destino quando
    há dados suficientes do destinatário.
- Regras fiscais de saída e o campo `CFOP de venda` não aceitam mais famílias
  de entrada em novas gravações.
- A validação usa o snapshot final do item da pré-nota, portanto também cobre
  correções manuais antes da emissão.

## Consequência operacional

Se não houver configuração fiscal segura, a nota fica bloqueada com a causa e
nenhuma numeração é consumida. A nota já rejeitada, que possui número/chave,
deve ser corrigida e retransmitida; não pode ser descartada como pré-nota.

## Próximo passo arquitetural

Substituir progressivamente a natureza textual por um cadastro estruturado de
naturezas/regras com versão, vigência e explicação persistida da decisão fiscal
por item.

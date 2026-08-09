# Decisao tecnica - Motor fiscal RTC IBS/CBS/IS

Data: 25/06/2026

## Contexto

O ERP Lyncar/PapezzoSync ja emitia NFC-e/NF-e no modelo fiscal atual. Foi implementada a convivencia com o novo modelo da Reforma Tributaria do Consumo, sem remover o motor antigo.

## Decisao

O motor fiscal passa a decidir a emissao por item/produto:

- produto sem campos de RTC preenchidos continua emitindo pelo modelo antigo;
- produto com IBS/CBS preenchido emite grupo `IBSCBS`;
- produto com Imposto Seletivo preenchido emite grupo proprio `IS`;
- uma mesma venda pode misturar itens antigos e novos.

O sistema nao inventa CST/cClassTrib/aliquotas. Ele usa apenas dados vindos do XML de entrada ou preenchidos no cadastro do produto.

## Recebimento de XML

Quando o XML do fornecedor trouxer IBS/CBS ou IS, o recebimento grava esses dados no item da entrada e, ao vincular/cadastrar o produto, preenche o cadastro fiscal do produto e ativa `new_tax_system`.

## Imposto Seletivo

IS fica em grupo proprio, separado de IBS/CBS. Campos relevantes:

- `CSTIS`
- `cClassTribIS`
- `vBCIS`
- `pIS`
- `pISEspec`
- `uTrib`
- `qTrib`
- `vIS`

## Validacao

Testado em homologacao SEFAZ com Drika Padaria:

- NFC-e antiga autorizada;
- NF-e antiga autorizada;
- NFC-e com IBS/CBS autorizada;
- NF-e com IBS/CBS autorizada;
- NFC-e com IBS/CBS + IS autorizada;
- NF-e com IBS/CBS + IS autorizada.

Chaves de validacao com IS:

- NFC-e: `35260663816719000115650010000000301714747145`
- NF-e: `35260663816719000115550010000000101069094803`

## Entrega ao servidor

Entrega criada em `E:\ATUALIZACAO_FISCAL_RTC_IBS_CBS_IS_2026-06-25`, contendo codigo, build web e instrucoes de migracao/deploy.

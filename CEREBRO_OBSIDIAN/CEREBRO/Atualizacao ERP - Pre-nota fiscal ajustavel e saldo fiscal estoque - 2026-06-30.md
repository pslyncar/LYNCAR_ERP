# Atualizacao ERP - Pre-nota fiscal ajustavel e saldo fiscal estoque - 2026-06-30

## Objetivo
Permitir emissao fiscal a partir de uma venda sem alterar a venda original, usando uma pre-nota/rascunho fiscal ajustavel.

## Regra central
A venda original nunca e editada pelo fluxo fiscal. O ajuste vale somente para a nota.

## Fluxo implementado
- Notas fiscais > Emitir nota pede o numero da venda.
- Carrega venda finalizada e monta rascunho fiscal.
- Usuario pode trocar produto fiscal, excluir item da nota e alterar valor unitario fiscal.
- Trocar produto abre busca por nome/codigo/codigo de barras/codigo pacote.
- Busca mostra estoque atual, saldo fiscal disponivel e entradas com nota.
- Preparar nota grava `fiscal_document_items` como auditoria.

## Auditoria
Tabela nova: `fiscal_document_items`.
Guarda item original, produto fiscal escolhido, valores, inclusao/exclusao, motivo e usuario.

## Estoque fiscal do produto
Campos adicionados ao produto:
- `fiscal_received_quantity`
- `fiscal_issued_quantity`
- `fiscal_available_quantity`
- `fiscal_entry_count`

Valores recalculados por entradas confirmadas e documentos fiscais autorizados.

## Motor Fiscal
Motor SEFAZ nao foi refeito. A camada de pre-nota cria uma visao fiscal da venda antes do motor.
Fluxo antigo continua se o documento nao tiver itens fiscais ajustados.

## Entrega
Pasta:
`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_ERP_SITE_2026-06-30_PRE_NOTA_FISCAL_ESTOQUE`
Zip:
`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_ERP_SITE_2026-06-30_PRE_NOTA_FISCAL_ESTOQUE.zip`

## Validacao
- py_compile OK
- FastAPI OpenAPI OK
- migrate_local OK
- flutter analyze OK
- flutter build web OK

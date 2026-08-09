# 2026-06-30 - GTIN unico e ofertas com periodo

## Contexto
Foi identificado que o cadastro de produtos permitia repetir o mesmo GTIN/codigo de barras em mais de um produto. Isso pode fazer o PDV, recebimento e emissao fiscal localizarem o produto errado.

Tambem foi solicitado cadastro de oferta com data e hora de inicio/fim.

## Alteracoes
- Backend impede criar/editar produto com GTIN ja usado por outro produto.
- A validacao considera:
  - `barcode` / codigo da unidade / EAN de venda;
  - `purchase_package_barcode` / codigo do pacote/embalagem.
- GTIN vazio continua permitido.
- Nao foi criado indice unico no banco para nao quebrar bases antigas com duplicidades; a regra impede novos duplicados pela API.

## Ofertas
- Produto recebeu:
  - `offer_price`
  - `offer_start_at`
  - `offer_end_at`
- ERP mostra campos de oferta no cadastro/edicao do produto.
- Formato visual: `dd/mm/aaaa hh:mm`.
- PDV e vendas usam `effectiveSalePrice`:
  - preco de oferta se estiver ativo;
  - preco normal fora do periodo.
- Carrinho offline do PDV preserva o `unit_price` salvo.

## Banco
Migracao adiciona colunas em `products`:
- `offer_price`
- `offer_start_at`
- `offer_end_at`

## Entrega
Pacote completo em:
`E:\ENTREGAS_CLIENTES\ATUALIZACAO_ERP_SITE_2026-06-30_GTIN_OFERTAS_PRE_NOTA.zip`

Esse pacote tambem inclui a entrega anterior da pre-nota fiscal em telas separadas com GTIN.

## Validacao
- Python compile ok.
- Migracao local ok.
- Dart format ok.
- Flutter analyze sem erros.
- Flutter build web gerado.

## Observacao
Motor fiscal SEFAZ nao foi alterado.

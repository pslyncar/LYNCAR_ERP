# 2026-08-09 - Limpeza de fotos orfas de produtos

## Problema

Ao remover ou trocar a foto de um produto, o sistema limpava o `image_url` no banco, mas mantinha o arquivo fisico em `uploads/tenant-products-CODIGO`. Como o master calcula uso de arquivos olhando a pasta de uploads, imagens antigas continuavam contando MB mesmo sem produto usando a foto.

## Ajuste

- `backend/app/services/uploads.py`: criado helper seguro para apagar arquivo publico apenas quando a URL pertence exatamente ao escopo esperado.
- `backend/app/api/routes/products.py`: ao trocar/remover foto de produto ou excluir produto, o backend apaga a foto antiga se nenhum outro produto usa a mesma `image_url`.
- `backend/app/migrate_local.py`: a atualizacao do servidor limpa imagens orfas antigas das pastas `tenant-products-CODIGO`, comparando arquivos fisicos com as URLs ainda usadas em `products.image_url`.

## Segurança

A exclusao fisica fica limitada a arquivos dentro da pasta esperada do tenant. URLs fora de `/public/tenant-products-CODIGO/arquivo` sao ignoradas.

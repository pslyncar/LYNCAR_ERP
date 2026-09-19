# Checklist de desempenho do cardápio PedeOn

Este documento registra o que o servidor Debian deve verificar para complementar
as otimizações feitas no frontend. A alteração do frontend não muda o contrato
da API nem o fluxo de pedidos.

## Imagens

- Medir o tamanho em bytes e as dimensões das capas, logos e imagens dos
  produtos realmente entregues em produção.
- Evitar entregar fotos originais grandes para o celular. Gerar versões
  otimizadas (por exemplo, WebP/AVIF ou JPEG progressivo) próximas do tamanho
  exibido, mantendo a original apenas para consulta/edição.
- No Flutter Web, `cacheWidth` e `cacheHeight` não reduzem o download nem o
  decode feito pelo navegador. Por isso o redimensionamento precisa acontecer
  no upload, no endpoint de imagens ou no proxy/CDN do servidor.
- Confirmar que as URLs públicas retornam `Content-Type` correto e compressão
  adequada quando aplicável.
- Configurar cache de longa duração para arquivos versionados, por exemplo
  `Cache-Control: public, max-age=31536000, immutable`.
- Confirmar que o proxy reverso/CDN não está redimensionando ou recomprimindo a
  mesma imagem a cada requisição.

## API e banco

- Medir no Debian o tempo de `GET /pedeon/public/{slug}` e separar tempo de
  consulta, serialização e transferência.
- A implementação atual consulta todas as publicações candidatas e filtra
  parte delas em Python antes de aplicar a paginação. Com muitos produtos,
  isso deve ser convertido em filtros SQL e paginação no banco, mantendo a
  resposta atual.
- Verificar índices para loja, produto ativo, canal, publicação e ordem de
  exibição.
- Confirmar que a API não está retornando campos ou grupos de modificadores
  desnecessários para a listagem inicial.
- Manter `page_size` limitado e testar a primeira página e as páginas seguintes
  com catálogo grande.

## Debian e entrega

- Verificar latência entre o domínio do cardápio, o proxy reverso e a API.
- Conferir HTTP/2 ou HTTP/3, keep-alive e cache do proxy reverso.
- Confirmar que os arquivos estáticos do Flutter são servidos com cache e que
  o `main.dart.js` não está sendo reconstruído ou baixado repetidamente.
- Repetir o teste em celular com cache frio e cache quente, observando tamanho
  transferido, tempo de carregamento e chamadas repetidas.

## Critério de validação

O teste deve usar um catálogo representativo, com várias categorias e imagens,
e medir: tempo até aparecer o primeiro conteúdo, tamanho total baixado,
requisições de imagem repetidas e frames perdidos durante a rolagem.

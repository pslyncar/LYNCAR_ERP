# PedeOn Etapa 08 - Separação por canal

Status: Implementada localmente / validação de fluxo pendente

## Objetivo

Diferenciar claramente PedeOn online, salão/QR, garçom, balcão e integrações.

## Implementar

- Ícone, nome e cor por origem.
- Filtros por online, salão e balcão.
- Preservar origem em cozinha, expedição, caixa, impressão e venda.
- Mostrar mesa/comanda apenas quando aplicável.

## Aceite

O operador identifica de onde veio o pedido sem interpretar texto livre.
## Implementação registrada

- O `source_channel` agora é apresentado com nomes compreensíveis: Online, Salão, Balcão, iFood e 99Food.
- O cabeçalho dos pedidos usa cores diferentes para Salão, Balcão e demais origens.
- O detalhe/recebimento do pedido usa ícones e rótulos coerentes com a origem.
- `pdv_counter` não é mais confundido visualmente com pedido de Salão.
- Os indicadores de pendências existentes no menu do PDV foram preservados.

## Validação local

- `flutter analyze` executado com sucesso.
- Ainda é necessário testar pedidos reais Online, Salão e Balcão atravessando o Edge, confirmando que cada canal permanece separado.
- Na etapa anterior, nenhum commit/push havia sido feito; o PDV operacional PedeOn continua somente local e permanece fora desta publicação.

## Regra consolidada do catálogo Online, Salão e Balcão

- `pedeon_online` é o canal público do cardápio online.
- `onsite_waiter` é o canal do Salão, servido localmente pelo Edge para o PDV PedeOn.
- `pdv_counter` é o canal de venda de balcão no PDV PedeOn.
- `onsite_qr` era um nome antigo usado pela tela administrativa. Ele permanece aceito somente como compatibilidade e é convertido para `onsite_waiter`; não deve mais ser gravado nem exibido como um canal separado.
- O cache operacional do Edge mantém Salão e Balcão para o PDV PedeOn. O catálogo usado pelo cardápio do Salão filtra somente `onsite_waiter`, evitando misturar produtos liberados apenas no Online.
- Categorias e produtos são filtrados por canal; ativar um produto no Online não o ativa automaticamente no Salão, e vice-versa.

## Correção aplicada em 2026-09-17

- A tela administrativa passou a gravar `onsite_waiter` ao ativar Salão.
- O backend passou a normalizar publicações antigas `onsite_qr` antes de montar os catálogos.
- O endpoint de catálogo do Edge agora filtra para o Salão quando solicitado com `channel=onsite_waiter`, entregando somente os produtos liberados para esse canal e apenas as categorias correspondentes; sem esse parâmetro, mantém o catálogo operacional completo para o PDV.
- O aplicativo operacional do PedeOn não foi alterado nem incluído em commit/push nesta etapa.

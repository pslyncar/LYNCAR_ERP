# 2026-07-03 - Ficha técnica e Produção com pesquisa

## Ficha técnica / composição
- O seletor de componente da ficha técnica não deve filtrar apenas insumo/matéria-prima/embalagem.
- Agora lista todos os produtos ativos, exceto o próprio produto que está recebendo a composição.
- O campo de componente abre uma janela pesquisável por nome, código interno, código de barras ou tipo.
- A composição continua salvando o produto escolhido como componente normalmente.

## Produção
- A tela de Produção mantém a regra de produto acabado/produto produzível.
- O campo Produto acabado deixou de ser dropdown simples e passou a abrir janela pesquisável.
- Pesquisa por nome, código interno ou código de barras.

## Validação
- flutter analyze sem erros.
- build web gerado sem service worker para evitar cache antigo.

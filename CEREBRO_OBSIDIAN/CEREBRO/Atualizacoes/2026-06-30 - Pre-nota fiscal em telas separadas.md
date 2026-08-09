# 2026-06-30 - Pre-nota fiscal em telas separadas

## Contexto
O cliente pediu para separar o fluxo de emissão manual de NF-e/NFC-e. Antes a tela misturava pesquisa da venda, seleção do tipo de nota e edição de itens no mesmo modal.

## O que foi alterado
- Criado fluxo em duas etapas:
  1. pesquisar a venda;
  2. montar a nota fiscal.
- A montagem da nota permite escolher NFC-e/NF-e depois que a venda é carregada.
- A venda original não é alterada.
- Produtos da pré-nota mostram código antes do nome.
- Ação de excluir item agora remove o item da nota, mantendo apenas o registro interno como `included=false`.
- Adicionado suporte para:
  - substituir produto fiscal;
  - adicionar produto fiscal;
  - alterar valor unitário;
  - editar descrição fiscal que sai na nota.
- Janela de estoque abre com lista inicial de produtos e permite busca por nome/código/código de barras.
- A lista de estoque mostra código, nome, estoque, valor e saldo fiscal/com nota.

## Backend
- `/fiscal/products/lookup` aceita busca vazia e retorna até 200 produtos ativos.
- `/fiscal/documents/prepare-with-items` aceita `fiscal_description` e `unit`.

## Importante
- O motor fiscal SEFAZ não foi alterado.
- A mudança é somente na camada de preparação/pré-nota.
- A autorização continua usando o motor fiscal existente.

## Validação local
- `python -m py_compile` nos arquivos backend alterados.
- `dart format`.
- `flutter analyze` sem erros.
- `flutter build web --release` com sucesso.
- Service worker removido do build para evitar cache antigo.

## Entrega
Pacote gerado em:
`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_ERP_SITE_2026-06-30_PRE_NOTA_TELAS_SEPARADAS.zip`

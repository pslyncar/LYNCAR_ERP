# 2026-07-01 - App mobile/site app: leitor com zoom e cadastro de produto

## Objetivo

Melhorar a leitura de codigos pequenos no app Android e no site do app sem mudar o visual geral, apenas acrescentando recursos ao leitor.

Adicionar cadastro de produto direto pelo app para clientes que tem dificuldade de cadastrar pelo ERP web.

## O que foi implementado

- MobileScanner com `autoZoom: true` no recebimento e na baixa de estoque.
- Controle visual de apoio ao leitor:
  - botao "Codigo pequeno / zoom";
  - slider de zoom manual;
  - botao de lanterna quando aparelho/navegador suportar.
- Nova ficha mobile de cadastro de produto:
  - nome;
  - codigo de barras/EAN;
  - codigo interno;
  - tipo;
  - unidade;
  - estoque atual;
  - estoque minimo;
  - preco de venda;
  - dados de compra;
  - marca;
  - categoria;
  - NCM;
  - CFOP;
  - descricao.

## Isolamento por cliente

O cadastro pelo app usa `ApiClient.createProduct(token, ProductPayload)`.

Portanto, o produto e gravado usando o token da sessao do usuario logado e depende da resolucao de tenant/empresa do backend. Nao foi criada rota global nem gravacao fora do contexto da empresa.

## Regras importantes

- No recebimento, se o codigo lido nao pertence ao recebimento selecionado, o sistema continua nao lancando o item naquele recebimento.
- O cadastro de produto no recebimento fica como acao separada para evitar entrada errada.
- Na baixa de estoque, se o produto nao for encontrado, o app pergunta se deseja cadastrar.
- A tela tambem tem botao manual "Cadastrar produto".

## Arquivos principais alterados

- `admin_app/admin_flutter/lib/screens/mobile_receiving_screen.dart`
- `admin_app/admin_flutter/lib/screens/mobile_stock_withdrawal_screen.dart`
- `admin_app/admin_flutter/lib/screens/mobile_product_form_sheet.dart`
- `admin_app/admin_flutter/lib/widgets/mobile_scanner_assist_controls.dart`

## Validacao

- `flutter analyze` executado sem erros.
- `flutter build web --release` executado com sucesso.
- `flutter build apk --release` gerou APK em `build/app/outputs/flutter-apk/app-release.apk`.

## Entrega

Como a unidade E: nao estava montada na sessao, a entrega foi deixada em:

`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_LEITOR_ZOOM_CADASTRO_PRODUTO_2026-07-01`

Zip:

`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_LEITOR_ZOOM_CADASTRO_PRODUTO_2026-07-01.zip`


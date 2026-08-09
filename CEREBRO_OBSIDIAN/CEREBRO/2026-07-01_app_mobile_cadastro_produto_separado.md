# 2026-07-01 - App mobile: cadastro de produto separado

## Contexto
O cadastro de produto no app Android/site app estava ficando dentro do fluxo de Recebimento de mercadorias. Isso gerou confusao porque a tela inicial mostrava apenas Recebimento de mercadorias e Baixa de estoque, e o cadastro so aparecia ao tentar ler produto nao encontrado.

## Decisao
Cadastro de produto deve ser modulo separado na tela inicial do app, igual um botao/card proprio. Recebimento deve continuar sendo apenas conferencia/recebimento de itens da entrada.

## Implementado
- Tela inicial do app agora tem card **Cadastrar produto**.
- O card aparece somente quando o usuario possui permissao `products:create`.
- Removido o cadastro rapido de dentro do Recebimento.
- Quando o produto nao estiver cadastrado/vinculado no recebimento, o app orienta cadastrar pelo modulo **Cadastrar produto** no inicio do app ou vincular pelo computador.
- Cadastro de produto pelo app usa token/sessao da empresa logada, sem misturar banco de clientes.
- Cadastro mobile inclui conversao pacote/caixa/embalagem para unidade:
  - unidade que vem na nota/XML;
  - unidades por pacote/embalagem;
  - codigo do pacote/caixa/embalagem.
- Mantidas melhorias de leitura de codigo pequeno: auto zoom, botao de zoom, controle manual de zoom e lanterna quando disponivel.

## Arquivos principais
- `admin_app/admin_flutter/lib/screens/mobile_app_dashboard_screen.dart`
- `admin_app/admin_flutter/lib/screens/mobile_product_form_sheet.dart`
- `admin_app/admin_flutter/lib/screens/mobile_receiving_screen.dart`
- `admin_app/admin_flutter/lib/screens/mobile_stock_withdrawal_screen.dart`
- `admin_app/admin_flutter/lib/widgets/mobile_scanner_assist_controls.dart`

## Validacao
- `dart format`: ok
- `flutter analyze`: sem erros
- `flutter build web --release`: ok
- `flutter build apk --release`: ok

## Entrega local
Como a unidade E: nao estava disponivel no momento da entrega, o pacote foi deixado em:

- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_CADASTRO_PRODUTO_SEPARADO_2026-07-01`
- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_CADASTRO_PRODUTO_SEPARADO_2026-07-01.zip`

Quando E: voltar, copiar essa pasta/zip para `E:\ENTREGAS_CLIENTES`.

# 2026-07-01 - Correcao: scanner de codigo somente no app

## Contexto
Foi solicitado que o cadastro de produto do app Android/site app tivesse o campo de codigo com icone para escanear pela camera. Houve interpretacao errada inicial colocando o scanner no ERP web. Essa alteracao do ERP foi descartada e nao deve ser entregue ao servidor.

## Decisao final
- ERP web principal: nao receber scanner no cadastro de produto nesta entrega.
- App Android/site app: cadastro de produto separado deve ter scanner no campo Codigo de barras / EAN.

## Entrega correta
- Cadastro de produto separado na tela inicial do app.
- Recebimento continua apenas conferindo/recebendo produto da nota/entrada.
- Cadastro de produto do app com lista de tipos alinhada ao ERP.
- Campo Codigo de barras / EAN do app com botao de scanner/camera.
- Mantidas melhorias de leitura de codigo pequeno.

## Validacao
- `dart format`: ok
- `flutter analyze`: sem erros
- `flutter build web --release`: ok
- `flutter build apk --release`: ok

## Pacote correto
- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_CADASTRO_PRODUTO_SCANNER_2026-07-01`
- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\APP_MOBILE_CADASTRO_PRODUTO_SCANNER_2026-07-01.zip`

## Observacao para servidor
Publicar somente o site app e APK. Nao aplicar pacote de ERP web referente a scanner de produto, pois ele foi removido.

# Fonte canonico do PDV Windows 1.0.51

Em 01/08/2026 foi confirmado que o servidor guardava uma copia parcial ou antiga
do fonte Flutter do PDV, embora o binario publicado 1.0.51 contivesse o consumidor
dos comandos remotos.

## Fonte oficial

- PDV Windows: `C:\PDV_ATUAL\app_flutter`
- Entrada de producao: `lib\main_pdv.dart`
- ERP Web/backend: `C:\erp_build` (projeto separado; nao confundir)

## Comandos remotos do PDV

O consumidor esta em `lib\pdv\logic\pdv_terminal_logic.dart` e o cliente HTTP em
`lib\services\api_client.dart`. Inclui reconexao, sincronizacao offline,
bloqueio/desbloqueio e reset do vinculo do terminal.

## Regra obrigatoria de publicacao

Toda versao publicada do PDV Windows deve guardar, ao lado do ZIP binario:

1. snapshot completo e limpo do fonte que gerou a versao;
2. versao alinhada no `pubspec.yaml` e em `PDV_APP_VERSION`;
3. manifesto SHA-256 dos arquivos;
4. comando de build de producao documentado;
5. ausencia de `build`, `.dart_tool`, caches, dados locais e chaves de assinatura.

## Entrega de reconciliacao

`C:\Users\vpape\Documents\FONTE_COMPLETO_PDV_WINDOWS_1.0.51_20260801_FINAL.zip`

Validado com `flutter analyze` e `flutter build windows --release`. O `app.so`
gerado confirmou as strings `/pdv/terminals/commands`, `force_reconnect`,
`sync_offline_sales`, `block_terminal` e `reset_terminal_link`.

Esta entrega de fonte nao publica nem força atualizacao nos clientes instalados.

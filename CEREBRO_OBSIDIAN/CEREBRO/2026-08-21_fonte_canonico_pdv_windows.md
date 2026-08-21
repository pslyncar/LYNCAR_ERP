# Fonte canonico atual do PDV Windows

## Regra sem excecao

O unico repositorio fonte permitido para corrigir, testar e versionar o
aplicativo PDV Windows e:

- repositorio Git: `C:\LYNCAR_PDV_APP_WINDOWS`
- remoto: `https://github.com/pslyncar/LYNCAR_PDV_APP_WINDOWS.git`
- branch oficial: `main`
- entrada do aplicativo: `C:\LYNCAR_PDV_APP_WINDOWS\lib\main_pdv.dart`
- tela operacional: `C:\LYNCAR_PDV_APP_WINDOWS\lib\screens\pdv_screen.dart`
- logica modular: `C:\LYNCAR_PDV_APP_WINDOWS\lib\pdv`
- versao encontrada em 21/08/2026: `1.0.52+52`
- ultima versao publicada confirmada pelo usuario: `1.0.51`

O aplicativo instalado em `C:\Program Files\Lyncar PDV` nunca deve ser usado
como pasta de desenvolvimento, teste ou build.

`C:\PDV_ATUAL\app_flutter` e uma copia de trabalho/build que em 21/08/2026 tinha
o mesmo ponto de partida 1.0.52, mas nao possui `.git`. Ela nao e a fonte de
verdade e nenhuma correcao pode ficar somente nela.

## Projeto que nao e o PDV Windows

`C:\erp_build\admin_app\admin_flutter` pertence ao ERP Web/admin. Ele possui
arquivos com nomes semelhantes (`main_pdv.dart`, `pdv_screen.dart` e
`api_client.dart`), mas nao e o fonte canonico do instalador Windows. Nao portar
uma tela inteira entre os dois projetos e nao executar o PDV Windows por essa
pasta.

O backend/API continua em `C:\erp_build\backend` e e compartilhado pelo ERP e
pelo PDV. Portanto, alteracoes de endpoints ficam no ERP, enquanto o consumidor
Windows deve ser implementado no fonte canonico acima.

## Incidente identificado em 21/08/2026

O commit `9e3fc7c feat(fiscal,pdv): conclui emissao e sincronizacao do caixa`
publicou corretamente no ERP/backend os endpoints de sincronizacao, WebSocket,
precificacao e comandos de carga. Contudo, o consumidor Flutter foi colocado na
copia do admin em `C:\erp_build\admin_app\admin_flutter`, nao no fonte canonico
do PDV Windows.

A correcao foi portada para `C:\LYNCAR_PDV_APP_WINDOWS` preservando:

- ativacao por codigo (`/auth/pdv/activate-terminal`);
- heartbeat e comandos remotos existentes;
- arquitetura modular da versao atual;
- cache e operacao offline;
- entrada e saida automatica da contingencia;
- sincronizacao incremental de produtos, clientes e ofertas via WebSocket;
- consulta REST a cada 30 segundos como redundancia;
- carga completa no inicio, a cada seis horas e por comando remoto;
- atualizacao de precos que ja estejam no carrinho, com aviso ao operador.

## Checklist antes de qualquer build/publicacao

1. Confirmar que o diretorio de trabalho e `C:\LYNCAR_PDV_APP_WINDOWS`.
2. Confirmar ativacao por **Codigo de ativacao**, nunca login comum por e-mail.
3. Conferir `version` em `pubspec.yaml` e `PDV_APP_VERSION` no fonte.
4. Executar `dart format` somente nos arquivos alterados.
5. Executar `flutter analyze`.
6. Executar os testes relevantes com `flutter test`.
7. Gerar o build em uma pasta de saida separada; nunca substituir a instalacao
   local usada pelo usuario durante desenvolvimento.
8. Guardar fonte, binario e manifesto SHA-256 da mesma versao.

## Fonte historico da 1.0.51

Snapshot confirmado:
`C:\Users\vpape\Documents\FONTE_COMPLETO_PDV_WINDOWS_1.0.51_20260801_FINAL.zip`.

Esse ZIP e referencia historica da 1.0.51. O repositorio canonico atual e
`C:\LYNCAR_PDV_APP_WINDOWS`, que deve estar alinhado com `origin/main` antes de
cada manutencao e publicacao.

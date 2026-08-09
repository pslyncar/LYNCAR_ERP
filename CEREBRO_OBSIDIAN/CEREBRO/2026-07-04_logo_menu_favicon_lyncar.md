# 2026-07-04 - Logo menu lateral e favicon Lyncar

- Menu lateral do ERP web passou a usar `assets/brand/lyncar_logo_clean.png` em vez de `LogoPGN.PNG`.
- Logo do menu expandido aumentada e moldura deixada mais sutil.
- `web/favicon.png` substituído por favicon gerado da logo Lyncar para remover ícone PS do navegador.
- Build web gerado e service worker removido para reduzir cache antigo.
- Entrega criada em E:\ATUALIZACAO_LOGO_MENU_FAVICON_LYNCAR_2026-07-04.

## Correção complementar favicon
- A logo horizontal Lyncar inteira ficou escura/ilegível como favicon.
- Favicon foi substituído por ícone simplificado `Ly`, fundo azul arredondado e letras claras, próprio para aba do navegador.

## Correção complementar favicon moderna
- Favicon simplificado azul claro ficou legível mas genérico.
- Nova versão: ícone `Ly` com fundo escuro/azul em gradiente e borda sutil, mais alinhado à identidade Lyncar.
- Pacote mantido em C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs.

## Favicon definitivo
- Usuário escolheu a imagem `C:\Users\vpape\OneDrive\Pictures\LY.png` como favicon oficial do navegador.
- A imagem foi copiada para `admin_app/admin_flutter/web/favicon.png` e `build/web/favicon.png`.
- Atualizações antigas de logo/favicon geradas pelo Codex foram apagadas para evitar confusão.

## Correção tamanho favicon LY.png
- A imagem `LY.png` original era ampla e deixava o ícone pequeno na aba.
- Foi gerado `web/favicon.png` recortando somente o ícone central, em 128x128, para ocupar melhor o favicon.

## Favicon recriado com nova LY.png
- Usuário colocou uma nova `LY.png` em `C:\Users\vpape\OneDrive\Pictures\LY.png`.
- Favicon foi recriado recortando o ícone central da nova imagem.
- Atualizado em `web/favicon.png`, `build/web/favicon.png` e pacote em C:.

## Cache-bust completo de ícones PWA
- Atualizados favicon, apple-touch-icon e ícones PWA 192/512/maskable usando a nova LY.png.
- `index.html` e `manifest.json` usam `?v=20260704` para forçar navegadores/celulares a buscar ícones novos.
- Build web regenerado e service worker removido.
- Entrega limpa recriada em C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_LOGO_MENU_FAVICON_LYNCAR_2026-07-04.zip.

## 2026-07-17 - Correção após migração de notebook
- Após copiar o build para `C:\erp_build\web`, o favicon servido em `http://127.0.0.1:5000` ainda estava com o ícone antigo `PS`.
- Corrigido copiando os ícones oficiais de `C:\erp_build\admin_app\admin_flutter\web` para `C:\erp_build\web`.
- Atualizado `C:\erp_build\web\index.html` para usar `favicon.png?v=lyncar-20260717` e `apple-touch-icon.png?v=lyncar-20260717`, forçando o navegador a buscar o ícone correto.
- Favicon correto: ícone `LY`/Lyncar, fundo azul escuro, sem `PS`.

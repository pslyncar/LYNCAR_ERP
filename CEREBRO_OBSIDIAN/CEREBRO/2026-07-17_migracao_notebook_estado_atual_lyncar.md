# 2026-07-17 - Migração de notebook e estado atual do Lyncar

## Objetivo desta nota
Registrar o estado atual do projeto antes da troca de notebook, para que outro ambiente consiga continuar o desenvolvimento sem perder contexto.

## Código principal
- Repositório/local principal: `C:\erp_build`
- Backend: `C:\erp_build\backend`
- Flutter/ERP/app/PDV: `C:\erp_build\admin_app\admin_flutter`
- App PDV Windows usa entrypoint: `lib/main_pdv.dart`
- Build web sai em: `admin_app/admin_flutter/build/web`
- Build PDV Windows sai em: `admin_app/admin_flutter/build/windows/x64/runner/Release`
- Entregas e pacotes usados para servidor/clientes ficam também em `C:\LynkarTransfer` e em `outputs` do Codex.

## Arquitetura geral
- Backend Python/FastAPI com SQLAlchemy.
- Frontend Flutter/Dart para ERP web, site app/mobile web, Android e PDV Windows.
- PostgreSQL local em `localhost:5432`, banco local principal `papezzosync`.
- Multiempresa/tenant: cada cliente usa banco separado; master controla empresas, planos, cobranças, acesso e liberações.
- Master possui dados centrais compartilhados como base fiscal de referência e feriados centrais.

## Módulos principais atuais
- Master: empresas, planos, cobranças, configurações de pagamento, acessos/primeiro login, presença/online, loja Lyncar e auto-update do PDV.
- ERP cliente: dashboard, clientes, vendas, PDV web, caixa/fechamentos, financeiro/crediário, estoque, fornecedores, entradas XML, baixas de estoque, relatórios, produção/ficha técnica, fiscal, usuários/permissões.
- App mobile/site app: login próprio, recebimento de mercadorias, baixa de estoque e cadastro de produto pelo app.
- PDV Windows: caixa local instalado, número fixo de caixa/terminal, impressão, sangria, fechamento, gaveta, offline, atualização remota e NFC-e quando habilitado.

## Fiscal
- O XML de entrada alimenta cadastro, estoque, custo, unidade, conversão, NCM/origem e histórico da compra.
- A tributação de saída não deve copiar cegamente CST/CSOSN/CFOP/alíquotas da entrada.
- Saída fiscal é resolvida por cadastro fiscal do produto + regra fiscal de saída + regime/CRT da empresa + modelo da nota + ambiente.
- Existe separação entre NF-e/NFC-e, DANFE/DANFE NFC-e, eventos/cancelamento e assistente fiscal.
- Reforma tributária IBS/CBS/IS existe como camada preparada; em homologação pode haver exigência diferente de produção.
- Atenção: para MEI/CRT 4 e NFC-e modelo 65, o CSOSN aceito é restrito; o motor precisa proteger a saída.

## Assistente Fiscal Inteligente
- Funciona como camada auxiliar, não substitui o motor fiscal.
- Usa XMLs importados, histórico interno, NCM/CFOP/CEST/base fiscal central e regras por regime.
- Deve sugerir e alertar, nunca sobrescrever sem confirmação.
- Aviso obrigatório: sugestões fiscais devem ser conferidas pelo contador/responsável fiscal.

## PDV Windows
- Não deve depender de expiração visual de sessão enquanto caixa estiver aberto ou pausado.
- Pausar/fechar temporariamente com F8 deve permitir retorno normal sem travar bipagem.
- Fechamento real do caixa encerra o movimento.
- PDV possui auto-update remoto: consulta atualização ao abrir e em momento seguro, não durante venda/caixa em uso.
- Atualização remota usa pacote ZIP publicado em Cloudflare/R2 e valida SHA256.
- Instalador Inno é para primeira instalação; atualização remota deve trocar arquivos de forma silenciosa/controlada pelo updater.

## Impressão e caixa
- PDV imprime cupom fiscal/NFC-e, cupom não fiscal, sangria e fechamento.
- Impressão fiscal deve usar o caminho fiscal correto; sangria/fechamento usam recibos próprios.
- Gaveta conectada na impressora deve abrir por pulso ESC/POS quando configurado; ausência de gaveta não deve exibir erro.
- Abrir gaveta por atalho deve exigir autorização fiscal.

## Precisão de preço e crediário - correção crítica de 2026-07-16
- Problema: venda esperada de R$ 101,86 fechava R$ 101,85 porque o preço unitário era truncado para 2 casas.
- Correção: preço unitário de produto/oferta e `sale_items.unit_price` passam a aceitar 4 casas decimais.
- Totais, pagamentos, crediário e troco continuam fechando em centavos.
- Exemplo correto: `5 x 20,371 = 101,855 -> R$ 101,86`.
- Se produto antigo já está salvo como `20,37`, precisa corrigir o preço real manualmente uma vez; o sistema não consegue recuperar casas que já foram perdidas.
- Entrega relacionada: `ENTREGA_PRECISAO_PRECO_CREDIARIO_PDV_1.0.27_20260716`.

## Auto-update do PDV
- Tabelas no master esperadas: `pdv_app_versions`, `pdv_app_version_rollouts`, `pdv_terminal_update_logs`.
- Endpoint esperado: `/master/pdv/update/check`.
- Canais: test/beta/stable.
- O PDV deve baixar pacote, validar SHA256, fechar em momento seguro e aplicar atualização.
- Versões recentes trabalhadas: 1.0.24/1.0.25/1.0.26/1.0.27.

## Banco e dumps
- Antes de trocar máquina, gerar dump do PostgreSQL local.
- Nesta migração foi criado dump em `E:\MIGRACAO_LYNCAR_NOTEBOOK_2026-07-17\00_BANCO_LOCAL_POSTGRES`.

## Cuidados ao migrar
- Copiar `C:\erp_build` inteiro, não apenas Git, pois há muitos arquivos novos não rastreados.
- Copiar `.env` com cuidado porque contém credenciais locais.
- Copiar `C:\LynkarTransfer`, `C:\LyncarBuild`, outputs do Codex e cérebro Obsidian.
- No notebook novo, instalar Flutter, Visual Studio Build Tools/C++ Desktop, Python, PostgreSQL, Git, Android Studio/JDK, Inno Setup e dependências do backend.
- Rodar `flutter doctor`, `flutter pub get`, criar venv Python e instalar `backend/requirements.txt`.
- Restaurar banco local se quiser continuar testes locais.

## 2026-07-17 - Conferencia nesta maquina
- Codigo principal copiado de `D:\MIGRACAO_LYNCAR_NOTEBOOK_2026-07-17\01_CODIGO_PRINCIPAL_C_erp_build` para `C:\erp_build`.
- Cofre Obsidian copiado para `C:\erp_build\CEREBRO_OBSIDIAN\CEREBRO`.
- Dumps PostgreSQL copiados para `C:\erp_build\BANCO_LOCAL_POSTGRES`.
- Pacote `D:\PDV_ATUAL` copiado para `C:\PDV_ATUAL`.
- Backend: `.venv` criado em `C:\erp_build\backend\.venv` e dependencias de `requirements.txt` instaladas.
- Flutter: SDK da migracao localizado em `D:\MIGRACAO_LYNCAR_NOTEBOOK_2026-07-17\10_FERRAMENTAS_SDKS_USADAS\flutter`; foi necessario marcar o diretorio como `safe.directory` no Git por ter vindo de outro usuario/SID.
- Web local: build pronto servido em `http://127.0.0.1:5000` a partir de `C:\erp_build\web`.
- API local: senha local confirmada, `backend\.env` atualizado usando senha URL-encoded, banco `papezzosync` criado e dump `C:\erp_build\BANCO_LOCAL_POSTGRES\papezzosync_custom.dump` restaurado.
- Web local ativo em `http://127.0.0.1:5000`.
- API local ativa em `http://127.0.0.1:8000/docs`.
- Proximo passo necessario: instalar Visual Studio Build Tools com workload "Desktop development with C++" para builds Windows/PDV; depois rodar `flutter doctor` novamente e aceitar licencas Android se solicitado.

## 2026-07-17 - Base mais recente sem PDV 1.0.28
- Regra confirmada pelo usuario: usar sempre o mais recente, exceto a entrega `1.0.28`, que nao deve ser usada.
- Base oficial do PDV local mantida em `C:\PDV_ATUAL`, com updates `PDV_Lyncar_Update_1.0.26.zip` e `PDV_Lyncar_Update_1.0.27.zip`.
- Nenhum pacote `1.0.28` foi encontrado/copiadado em `C:\PDV_ATUAL`.
- Correção mais recente fora da 1.0.28 aplicada ao backend local: `D:\CORR_NF_ESTORNO\backend\app\api\routes\fiscal.py` copiado para `C:\erp_build\backend\app\api\routes\fiscal.py`.
- A correção adiciona estorno de estoque ao cancelar NF autorizada vinculada a venda, com trava para nao estornar duas vezes o mesmo documento fiscal.
- API reiniciada em `http://127.0.0.1:8000/docs` e web mantido em `http://127.0.0.1:5000`.

## 2026-07-17 - Restauracao banco Drika Padaria
- Dumps de tenants/localizados em `D:\BANCOS_LYNCAR_LOCAIS_20260717`.
- Banco `papezzosync_drika_padaria` restaurado a partir de `D:\BANCOS_LYNCAR_LOCAIS_20260717\01_DUMPS_POR_BANCO\papezzosync_drika_padaria.custom.dump`.
- URL da empresa `drika_padaria` no banco master ajustada para `postgresql+psycopg://postgres:Dell%40123@localhost:5432/papezzosync_drika_padaria`.
- Rodado `python -m app.migrate_local` para alinhar o schema antigo do tenant ao codigo atual.
- Login local validado via API com empresa `drika_padaria` e usuario `drika@gmail.com`.
- Senha local de teste do usuario `drika@gmail.com` resetada para `123456` nesta maquina para validar ambiente; tratar como senha temporaria/local.

## 2026-07-17 - Codigo alinhado com servidor atual
- Pacote de codigo atual do servidor localizado em `D:\ERP_ATUAL_SERVIDOR_20260717-214152`.
- Origem do pacote: `C:\Lynkar\ERP-PAPEZZOSYNC` do servidor; exportado sem `.env`, `.venv`, `.git`, uploads, build e caches.
- `C:\erp_build` sincronizado com o codigo do servidor, preservando configuracoes locais sensiveis e geradas: `.env`, bancos locais, `.venv`, `.git`, `node_modules`, `.dart_tool`, builds/caches e `local.properties`.
- Build web regenerado com Flutter a partir de `C:\erp_build\admin_app\admin_flutter` e publicado em `C:\erp_build\web`.
- Favicon correto `LY`/Lyncar mantido no build publicado.
- API reiniciada em `http://127.0.0.1:8000/docs` e web mantido em `http://127.0.0.1:5000`.
- Login local `drika_padaria` / `drika@gmail.com` validado com sucesso apos sincronizacao.
- Verificacao feita: nenhum pacote/arquivo `1.0.28` foi encontrado em `C:\PDV_ATUAL` ou `C:\erp_build`.

## 2026-07-17 - Terminais PDV no ambiente local
- Tela `Terminais` confirmada no frontend em `admin_app/admin_flutter/lib/screens/pdv_terminals_screen.dart`.
- Rotas confirmadas no backend em `backend/app/api/routes/pdv_terminals.py`, incluídas em `backend/app/api/router.py` com prefixo `/pdv`.
- Menu lateral mostra `Terminais` somente quando a sessao possui permissao `pdv_operators:manage`.
- Login local da Drika retorna a permissao `pdv_operators:manage`.
- Endpoint `GET http://127.0.0.1:8000/pdv/terminals` validado com token da Drika: resposta `200 []`.
- Build publicado em `C:\erp_build\web` contem a string `Terminais`; cache-bust do `index.html` atualizado para `20260717-servidor-terminal` e servidor web reiniciado.
- Observacao: lista vazia significa que ainda nao ha terminal cadastrado/heartbeat recebido; a tela deve aparecer, mas sem itens ate um PDV se registrar.

## 2026-07-17 - Ajuste menu Terminais perto do PDV
- O botao `Terminais` nao depende de existir terminal cadastrado; depende da permissao `pdv_operators:manage`.
- O usuario nao via o item porque ele estava mais abaixo no menu lateral rolavel, depois de `Relatorios`.
- Ajustado `admin_app/admin_flutter/lib/screens/app_shell.dart` para exibir `Terminais` e `Op. PDV` logo apos `PDV`.
- Como o Flutter build web foi bloqueado pelo Windows por falta de suporte a symlink/Modo Desenvolvedor, a mesma ordem foi aplicada no build publicado em `C:\erp_build\web\main.dart.js`.
- `C:\erp_build\web\flutter_bootstrap.js` tambem foi ajustado para carregar `main.dart.js?v=20260717-terminal-menu`, evitando cache antigo do navegador.
- Ordem publicada confirmada no arquivo servido: `PDV`, `Terminais`, `Op. PDV`, `Caixa`.
- Para gerar novamente pelo Flutter nesta maquina, ativar o Modo Desenvolvedor do Windows ou rodar em ambiente com permissao para symlinks.

## 2026-07-17 - Diagnostico correto Terminais/icone local
- Conferido depois: `admin_app/admin_flutter/lib/screens/app_shell.dart` local esta igual ao pacote do servidor `D:\ERP_ATUAL_SERVIDOR_20260717-214152` no trecho do menu.
- Portanto a diferenca era local: build publicado/cache/fonte antiga, nao regra de banco e nao codigo-fonte divergente.
- Sintoma visto: `Terminais` aparecia, mas o icone selecionado nao renderizava.
- Causa provavel: `C:\erp_build\web\assets\fonts\MaterialIcons-Regular.otf` estava como fonte reduzida de 35 KB do build antigo.
- Correcao local aplicada: substituida por fonte completa do Flutter SDK (`materialicons-regular.otf`, 1.6 MB) em `C:\erp_build\web\assets\fonts\MaterialIcons-Regular.otf` e no build local existente.

## 2026-07-17 - Chrome local validado
- API local e servidor web local foram reiniciados.
- Havia processos duplicados de API/web; foram encerrados e subidos novamente.
- Chrome confirmou carregamento de `main.dart.js` com cache-bust.
- Mesmo com fonte completa, o icone `devices_other` usado por `Terminais` nao renderizou nesta publicacao local.
- Para resolver sem alterar o fonte Dart igual ao servidor, o build publicado local `C:\erp_build\web\main.dart.js` foi ajustado para usar o icone de computador/dispositivo ja renderizado corretamente no menu.
- Cache-bust atualizado para `20260717-terminal-menu2`.
- Validacao visual no Chrome: `Terminais` aparece com icone no menu expandido.

## 2026-07-17 - Reversao ajuste manual icone Terminais
- Usuario pediu para nao alterar codigo/visual diferente do servidor.
- Revertido no build publicado local `C:\erp_build\web\main.dart.js` o icone alternativo usado temporariamente em `Terminais`.
- `Terminais` voltou a usar os mesmos simbolos compilados esperados do fonte do servidor: `devices_other_outlined`/`devices_other` (`B.a16`/`B.a0g` no JS minificado).
- Conferido: `admin_app/admin_flutter/lib/screens/app_shell.dart` local esta identico ao pacote do servidor `D:\ERP_ATUAL_SERVIDOR_20260717-214152`.
- Ordem definida pelo codigo do servidor nesse arquivo: `PDV`, `Terminais`, `Op. PDV`, `Caixa`.

## 2026-07-17 - Restauracao ordem original do servidor
- Usuario corrigiu que a referencia correta esta em `D:\ERP_ATUAL_SERVIDOR_20260717-214152`.
- Conferido fonte do servidor: ordem do menu e `PDV`, `Caixa`, depois mais abaixo `Terminais` e `Op. PDV` apos `Relatorios`.
- Restaurado `C:\erp_build\admin_app\admin_flutter\lib\screens\app_shell.dart` copiando do pacote do servidor.
- Hash SHA256 do `app_shell.dart` local ficou igual ao do servidor: `E565AC52AC949B4C8605067034768BCF9804A7199BFE36FFF310FCD0699D5ACB`.
- Corrigido tambem o build publicado local `C:\erp_build\web\main.dart.js` para a mesma ordem do servidor.
- Cache-bust atualizado para `20260717-servidor-ordem-original`.

## 2026-07-17 - Comparacao com site servidor Drika
- Usuario pediu comparar com `https://padariadrika.lyncar.com.br/` aberto no Chrome.
- Servidor carrega build versionado: `main.20260716202134.dart.js` e `flutter_bootstrap.20260716202134.js`.
- Servidor usa `serviceWorkerSettings: null` e `assets/FontManifest.json` apontando para `fonts/MaterialIcons-Regular.otf`.
- Baixado do servidor o `main.20260716202134.dart.js`, `flutter_bootstrap.20260716202134.js` e `assets/fonts/MaterialIcons-Regular.otf`.
- Local ajustado para usar esses arquivos versionados do servidor em `C:\erp_build\web`.
- Corrigido `C:\erp_build\web\assets\FontManifest.json` para voltar a apontar para `fonts/MaterialIcons-Regular.otf`, igual ao servidor; antes estava apontando para `MaterialIcons-Regular-full.otf`, alteracao local incorreta.
- Validado no Chrome local: menu voltou para ordem do servidor e icone de `Terminais` aparece.

## 2026-07-18 - Web publicado completo do servidor restaurado
- Usuario trouxe `C:\Users\vpape\Downloads\WEB_PUBLICADO_ERP_20260717-224707` com a pasta web publicada completa do servidor.
- `RESUMO_WEB_PUBLICADO.txt` confirma origem: `C:\Lynkar\ERP-PAPEZZOSYNC\admin_app\admin_flutter\build\web` no servidor.
- Instrucao do pacote: copiar/substituir a pasta inteira, nao rebuildar e nao misturar partes de outro build.
- `C:\erp_build\web` foi espelhado com `robocopy /MIR` a partir dessa pasta publicada.
- Extras locais incorretos removidos pelo espelhamento: `flutter_service_worker.js` e `assets/fonts/MaterialIcons-Regular-full.otf`.
- Hashes principais apos copia batem com o pacote publicado:
  - `index.html`: `A961C2EA608374BCCA68E7E80EE90D164CF02B8E7179D40A8694BACA33BB0F93`
  - `main.20260716202134.dart.js`: `C6D9CAF89364E21DA76C24902E62E9350BF09C77AAC99F4A80F0C3B0152C8744`
  - `assets/FontManifest.json`: `CD7E03645BC44B2DD47B7CB626F51C4ECBF55A197AB77241628B47AC165FBE21`
  - `assets/fonts/MaterialIcons-Regular.otf`: `90EC2AD6CDDAA9D3287475818A3FAC4997F73CD81299A3B8A79C92FF0E722F38`
- Servidor web local reiniciado em `http://127.0.0.1:5000` e respondeu 200.
- Validado no Chrome: tela local carrega a arte de login do build publicado do servidor.

## 2026-07-18 - Icone Terminais selecionado resolvido via localhost
- Depois de copiar o web publicado completo do servidor, `127.0.0.1:5000` ainda podia mostrar o icone de `Terminais` selecionado vazio por cache/estado antigo do Chrome.
- Validado tecnicamente: a fonte publicada `MaterialIcons-Regular.otf` contem os glyphs `devices_other_outlined` (`0xefba`) e `devices_other` (`0xe1cc`).
- Aberto o mesmo servidor local por `http://localhost:5000/`, que usa outro cache/origem no Chrome.
- Login local com `drika_padaria` / `drika@gmail.com` / senha local temporaria validou a tela.
- Ao selecionar `Terminais` em `http://localhost:5000/`, o icone apareceu corretamente.
- Conclusao: problema visual restante era cache/estado do Chrome para `127.0.0.1:5000`, nao codigo e nao pasta publicada.
- Recomendacao operacional nesta maquina: usar `http://localhost:5000/` para o web local, mantendo API em `http://127.0.0.1:8000`.

## 2026-07-18 - PDV Windows local aberto
- Usuario informou que instalou Visual Studio e pediu abrir o PDV app Windows, nao o web.
- C�rebro confirmou: PDV Windows separado usa `C:\PDV_ATUAL\app_flutter` com entrypoint `lib/main_pdv.dart`; nao confundir com ERP web/site.
- Flutter SDK nao foi encontrado no PATH nem nos caminhos antigos, entao foi usada entrega pronta do pacote local.
- Extraido `C:\PDV_ATUAL\updates\windows\PDV_Lyncar_Update_1.0.27.zip` para `C:\PDV_ATUAL\run_1_0_27_20260718`.
- Nao foi usada versao 1.0.28.
- API local estava ativa em `http://127.0.0.1:8000/docs` com resposta 200.
- Aberto executavel `C:\PDV_ATUAL\run_1_0_27_20260718\lyncar_pdv.exe`.
- Processo validado: janela `PDV Lyncar` respondendo.

## 2026-07-18 - PDV Windows apontando para local
- Usuario avisou que o PDV Windows abriu apontando para producao.
- Causa encontrada: `C:\Users\vpape\AppData\Roaming\Lyncar\PDV Lyncar\shared_preferences.json` tinha `apiBaseUrl` salvo como `https://api.lyncar.com.br` e `companyCode` vazio.
- Nao foi alterado codigo.
- Configuracao local ajustada para:
  - `apiBaseUrl`: `http://127.0.0.1:8000`
  - `companyCode`: `drika_padaria`
  - `email`: `drika@gmail.com`
  - `password`: senha local temporaria `123456`
- Login validado na API local: `POST /auth/login` retornou OK para `drika_padaria`.
- PDV reaberto em `C:\PDV_ATUAL\run_1_0_27_20260718\lyncar_pdv.exe`; janela `PDV Lyncar` respondendo.

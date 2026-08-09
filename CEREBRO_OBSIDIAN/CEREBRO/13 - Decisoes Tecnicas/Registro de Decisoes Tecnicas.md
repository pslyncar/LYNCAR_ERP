# Registro de Decisoes Tecnicas

## Decisoes iniciais consolidadas

### DT-001 - Backend com FastAPI

- Status: aceita.
- Contexto: o projeto precisa de uma API REST para conectar app administrativo, banco e agente.
- Decisao: usar Python com FastAPI.
- Consequencia: documentacao automatica via Swagger/OpenAPI e desenvolvimento rapido de endpoints.

### DT-002 - Banco principal PostgreSQL

- Status: aceita.
- Contexto: o ERP/CRM precisa de banco confiavel para filtros, relatorios e crescimento futuro.
- Decisao: usar PostgreSQL como primeira opcao.
- Consequencia: base robusta para dados relacionais e relatorios.

### DT-003 - Interface administrativa em Flutter

- Status: aceita.
- Contexto: o sistema precisa de interface para equipe interna.
- Decisao: criar app administrativo em Flutter/Dart.
- Consequencia: possibilidade de evoluir para web, desktop e mobile.

### DT-004 - Agente de monitoramento em Python

- Status: aceita.
- Contexto: computadores dos clientes devem enviar dados basicos de saude.
- Decisao: criar agente Python usando bibliotecas como `psutil`.
- Consequencia: coleta simples e extensivel, com atencao a privacidade.

### DT-005 - Duas interfaces principais

- Status: aceita.
- Contexto: equipe interna e clientes possuem necessidades diferentes.
- Decisao: manter app administrativo interno e portal/app do cliente separados, usando a mesma API central.
- Consequencia: melhora controle de permissoes e separacao de dados por cliente.

### DT-006 - Operador de PDV separado do usuario do ERP

- Status: aceita.
- Contexto: pessoas que operam caixa nao devem necessariamente ter acesso ao ERP/CRM completo.
- Decisao: criar cadastro proprio de operadores e fiscais de PDV com codigo e senha/PIN, separado de `users`.
- Consequencia: o app administrativo pode manter usuarios internos completos, enquanto o PDV usa credenciais simples e focadas na operacao de caixa.
- Alternativas consideradas: usar usuario do sistema como operador de caixa; rejeitado porque daria acesso administrativo desnecessario a pessoas que so precisam operar o caixa.

### DT-007 - PDV com modo focado e sessao protegida durante caixa aberto

- Status: aceita.
- Contexto: em operacao de caixa, a tela deve parecer um PDV de mercado e nao pode desconectar por inatividade enquanto o caixa estiver aberto.
- Decisao: adicionar modo focado/tela cheia dentro do app Flutter e manter atividade viva quando o caixa PDV estiver aberto.
- Consequencia: reduz interrupcoes na operacao de venda; ao fechar o caixa, a regra normal de inatividade volta a valer.
- Alternativas consideradas: desativar expiracao global do sistema; rejeitado por piorar seguranca nas telas administrativas.

### DT-008 - Separacao entre Vendas administrativas e PDV

- Status: aceita.
- Contexto: a assistencia tecnica usa Vendas como fluxo administrativo, enquanto o PDV atende operacao de caixa de comercios.
- Decisao: separar a tela administrativa de Vendas e a tela de PDV em arquivos Flutter diferentes.
- Consequencia: ajustes futuros no caixa devem ser feitos em `pdv_screen.dart`, reduzindo risco de alterar a venda administrativa por engano.
- Alternativas consideradas: manter tudo em `sales_screen.dart`; rejeitado porque mistura contextos de negocio diferentes.

### DT-009 - Inicio multiempresa com campo Empresa no login

- Status: aceita.
- Contexto: o sistema sera vendido para empresas diferentes, como padarias, mercados e a propria assistencia tecnica Papezzo.
- Decisao: iniciar a arquitetura multiempresa com campo `Empresa` no login, cadastro master de empresas e gravar a empresa na sessao/token.
- Consequencia: a interface ja fica preparada para selecionar a empresa e a API passa a resolver o banco pelo cadastro master.
- Alternativas consideradas: esperar compra de dominio para usar subdominio desde o inicio; rejeitado porque atrasaria testes locais.

### DT-010 - Superadmin master separado dos tenants

- Status: aceita.
- Contexto: o dono do PapezzoSync precisa controlar todo o sistema, clientes SaaS, bancos e planos, sem ser tratado como uma empresa cliente.
- Decisao: criar login master com empresa `master` e tabela `master_users`, separado dos usuarios de cada tenant.
- Consequencia: o painel master mostra apenas controles globais e o ERP vendido continua separado por empresa/tenant.
- Alternativas consideradas: usar a empresa `papezzosync` como painel master; rejeitado porque mistura dono do sistema com cliente/tenant.

### DT-011 - Servidor Windows com pasta de transferencia

- Status: aceita.
- Contexto: o servidor inicial sera um Windows 11 Pro e a maquina atual continuara como desenvolvimento.
- Decisao: usar pasta compartilhada somente como ponte de transferencia, mantendo o sistema rodando localmente no servidor em `C:\Lynkar\ERP-PAPEZZOSYNC`.
- Consequencia: reduz risco de travamento, lentidao e corrupcao por executar o sistema diretamente em compartilhamento de rede.
- Alternativas consideradas: rodar o projeto diretamente pela pasta compartilhada; rejeitado por instabilidade e risco operacional.

## Template

Usar [[00 - Entrada/Templates/Template - Decisao Tecnica|Template - Decisao Tecnica]] para novas decisoes.

## 2026-06-01 - Dominio de producao e sincronizacao do servidor

- Status: aprovado
- Contexto: o servidor Windows recebeu ajustes manuais para funcionar em producao e esses arquivos precisavam voltar para o ambiente de desenvolvimento local.
- Decisao: o dominio correto do produto e `lyncar.com.br` com C. Os arquivos enviados pelo servidor em `Z:\codex-server-changes-20260601-075305.zip` foram copiados exatamente para o projeto local, sem formatacao ou alteracoes manuais.
- Arquivos sincronizados:
  - `admin_app/admin_flutter/lib/screens/login_screen.dart`
  - `backend/app/schemas/auth.py`
  - `deploy/windows/server-start.ps1`
  - `deploy/windows/server-update.ps1`
  - `deploy/windows/server-start-all.ps1`
- Consequencias: futuras atualizacoes devem preservar `lyncar.com.br` com C e comparar/copiar os arquivos de servidor sem corrigir nomes automaticamente.

## 2026-06-01 - Login por dominio e sessao em cadastros

- Status: aprovado
- Contexto: o login com campo Empresa ficaria ruim para clientes SaaS, pois cada cliente tera seu proprio dominio/subdominio. Tambem foi observado que uma tela de cadastro podia continuar aberta por cima do login apos expiracao por inatividade.
- Decisao: remover o campo Empresa da tela de login. O app passa a inferir a empresa pelo host: `app.lyncar.com.br` e localhost entram no master; `codigo.erp.lyncar.com.br` usa `codigo` como tenant. A atividade do usuario passa a ser capturada globalmente, incluindo dialogs e telas de cadastro. Ao sair/expirar, rotas modais sao fechadas antes de exibir o login.
- Consequencias: novos clientes devem receber codigo/subdominio no cadastro de Empresas. O DNS/proxy devera apontar `*.erp.lyncar.com.br` para o app quando a infraestrutura estiver pronta.

## 2026-06-01 - Dominio master em erp.lyncar.com.br

- Status: aprovado
- Contexto: o painel master nao usara `app.lyncar.com.br`; o dominio principal do ERP deve ser mais simples.
- Decisao: `erp.lyncar.com.br` sera o login master/superadmin. Clientes SaaS usarao `codigo.erp.lyncar.com.br`. A API continua em `api.lyncar.com.br`.
- Consequencias: DNS/proxy deve apontar `erp.lyncar.com.br` e `*.erp.lyncar.com.br` para o app web, e `api.lyncar.com.br` para a API.

## 2026-06-01 - Identidade visual Lyncar no login e menu

- Status: aprovado
- Contexto: a marca do produto passou a usar os novos assets `fundolyncar.png` e `Logo.png` enviados pela pasta de transferencia.
- Decisao: substituir o fundo de login por `fundolyncar.png`, substituir a logo usada no menu/PDV/vendas por `Logo.png` e simplificar a tela de login para exibir apenas o card, sem mascote.
- Consequencias: os assets internos mantem os mesmos nomes para evitar alterar varias referencias no codigo, mas o conteudo visual agora e da marca Lyncar.

## 2026-06-01 - Ajuste responsivo do fundo de login Lyncar

- Status: aprovado
- Contexto: o fundo de login estava usando `BoxFit.cover`, cortando a arte em telas largas/baixas e deslocando visualmente o card.
- Decisao: usar a nova imagem `fundolyncar.png` enviada em Imagens/OneDrive, renderizar o fundo com `BoxFit.contain` sobre gradiente escuro e posicionar o card de login de forma responsiva: direita em telas grandes e centro em telas menores.
- Consequencias: a arte do fundo passa a ser preservada integralmente em diferentes tamanhos de tela, podendo aparecer area escura de respiro quando a proporcao do monitor for diferente da imagem.

## 2026-06-01 - Login Lyncar com fundo composto em Flutter

- Status: aprovado
- Contexto: a imagem unica de fundo nao se adaptava bem em todos os tamanhos de tela, cortando laterais ou criando faixas.
- Decisao: decompor a tela de login em camadas responsivas: fundo e efeitos em codigo Flutter (`CustomPainter`), logo Lyncar separada, detalhe do Y separado, credito PapezzoSync separado e card independente.
- Consequencias: a tela passa a se adaptar melhor a diferentes monitores, evitando depender de uma arte unica com tudo fixo.

## 2026-06-01 - Y decorativo do login desenhado em codigo

- Status: aprovado
- Contexto: o asset separado do detalhe do Y nao estava com proporcao/area transparente adequada e ficava desalinhado na tela.
- Decisao: substituir o uso visual do PNG `lyncar_y_detail.png` por um `CustomPainter` que desenha o Y grande com paths, gradiente azul, contorno e brilho.
- Consequencias: o Y passa a escalar proporcionalmente com a tela e nao depende mais de uma imagem fixa para a composicao principal.

## 2026-06-02 - Subdominio direto para clientes SaaS

- Status: aprovado
- Contexto: o login nao deve mais pedir campo Empresa. Cada cliente SaaS tera um link proprio, por exemplo `padaria.lyncar.com.br`, e o app deve descobrir a empresa pelo host acessado.
- Decisao: manter `erp.lyncar.com.br` como painel master/superadmin e usar `codigo.lyncar.com.br` para clientes. O `codigo` continua sendo a chave interna da empresa e tambem o subdominio publico. Subdominios reservados como `erp`, `api`, `www`, `master`, `app` e `lyncar` nao podem ser cadastrados como clientes.
- Consequencias: o cadastro master de Empresas passa a mostrar o link publico `https://codigo.lyncar.com.br`. A infraestrutura futura deve configurar DNS wildcard `*.lyncar.com.br` e proxy para entregar o app web, preservando `api.lyncar.com.br` para a API.

## 2026-06-02 - Indice master de usuarios SaaS

- Status: aprovado
- Contexto: os bancos dos clientes SaaS sao separados, mas o sistema precisa saber se um e-mail ja existe em outro cliente e redirecionar usuarios que tentarem logar no dominio errado.
- Decisao: criar a tabela master `master_user_index`, sem senha, contendo e-mail, nome, papel, empresa e status do usuario. Ao criar o primeiro admin da empresa ou usuarios do sistema, a API consulta este indice. Se o e-mail existir em outro cliente, a criacao exige confirmacao explicita (`allow_cross_company_duplicate`). No login master, se o e-mail nao for de superadmin mas existir em exatamente um cliente ativo, a API retorna o link correto para redirecionamento.
- Consequencias: os bancos dos clientes continuam isolados, mas o master passa a ter uma lista operacional minima de e-mails para controle, aviso de duplicidade e redirecionamento. Como dado pessoal, esse indice deve ser protegido e tratado pelas regras de LGPD.

## 2026-06-03 - Estoque com ficha tecnica como base de producao

- Status: aprovado
- Contexto: o ERP sera vendido para padarias, mercados, lojas e outros negocios. Padarias e mercados precisam controlar composicao de produtos e futura producao com baixa de materias-primas.
- Decisao: renomear o modulo visual de Produtos para Estoque e criar a tabela `product_composition_items`, ligada ao produto final e aos componentes cadastrados no estoque.
- Consequencias: a ordem de producao futura deve usar a ficha tecnica para gerar entrada do produto acabado e saida das materias-primas/insumos, registrando tudo no historico de estoque.
- Alternativas consideradas: controlar composicao apenas em texto no cadastro do produto; rejeitado porque nao permitiria baixa automatica nem custo estimado confiavel.

## 2026-06-03 - Ordem de producao movimenta estoque automaticamente

- Status: substituido pela decisao de 2026-06-06
- Contexto: padarias e mercados precisam produzir itens como paes, bolos e salgados a partir de materias-primas cadastradas.
- Decisao: criar ordens de producao concluidas imediatamente, usando a ficha tecnica para calcular consumo e criar movimentos de estoque.
- Consequencias: a operacao de producao passa a exigir ficha tecnica valida e estoque suficiente dos componentes. Cancelamento, rascunho e etapas intermediarias ficam para evolucao posterior.
- Alternativas consideradas: alterar estoque manualmente; rejeitado porque nao cria rastreabilidade nem baixa automatica dos insumos.

## 2026-06-06 - Ordem de producao com ciclo completo de ERP

- Status: aprovado e implementado localmente.
- Contexto: a producao nao deve ser apenas um botao que movimenta estoque na hora. Empresas como padarias, mercados e pequenas industrias precisam planejar, iniciar, concluir, auditar custos e cancelar/estornar quando necessario.
- Decisao: a OP passa a ter ciclo `planejada`, `em_producao`, `concluida` e `cancelada`. Criar OP nao altera estoque. Concluir OP baixa componentes pela ficha tecnica, entra produto acabado pelo custo real dos componentes e registra movimentos no historico. Cancelar OP concluida estorna o produto acabado e devolve componentes ao estoque/lote de retorno quando o produto acabado ainda nao saiu.
- Consequencias: a tela de Producao mostra previa oficial calculada pelo backend, status separados, custo estimado, custo real e acoes de iniciar/concluir/cancelar. A rastreabilidade fica em `production_orders`, `production_order_components`, `stock_movements` e `product_batches`.
- Alternativas consideradas: manter producao concluida imediatamente; rejeitado porque nao atende operacao real de ERP nem auditoria de estoque/custo.

## 2026-06-03 - Custo medio ponderado no estoque

- Status: aprovado
- Contexto: o cadastro de produtos precisava calcular corretamente custos como trigo 5 kg por R$ 25,00 usando 0,300 kg em uma ficha tecnica. Alem disso, o ERP deve nascer com uma base profissional para padarias, mercados, lojas e producao.
- Decisao: usar custo medio ponderado por movimentacao de entrada como regra principal de estoque. O cadastro pode informar valor de compra/base e quantidade base do custo para formar o custo inicial, mas ficha tecnica, producao, vendas e historico de estoque devem usar o custo medio atual.
- Consequencias: entradas recalculam `average_cost` e `stock_value`; saidas baixam o estoque pelo custo medio vigente; vendas continuam guardando preco de venda no documento comercial, mas o movimento de estoque registra custo/valor de estoque.
- Alternativas consideradas: usar apenas um campo de custo fixo no cadastro; rejeitado porque nao acompanha variacao de compras, nao atende CMV corretamente e gera custo errado em produtos vendidos por lote/pacote.
- Observacao: os campos oficiais sao `purchase_total_cost`, `purchase_quantity`, `average_cost` e `stock_value`. Referencias antigas usadas durante desenvolvimento devem ser apenas renomeadas por migracao e nao fazem parte do modelo final.

## 2026-06-04 - Entradas de estoque, XML NF-e e certificado por tenant

- Status: aprovado
- Contexto: o sistema precisa controlar entradas de mercadoria para recalcular custo medio e atender empresas como padarias, mercados e lojas. Tambem deve aceitar XML de NF-e enviado pelo fornecedor sem custo e preparar baixa automatica por chave quando houver certificado digital.
- Decisao: criar modulo de Entradas separado do cadastro de Estoque, com fornecedores, entradas, itens de entrada, importacao manual de XML e rota preparada para baixa por chave. O certificado digital e configuracao de cada empresa no cadastro master.
- Consequencias: cada tenant possui seus proprios fornecedores, entradas e XMLs. Entrada confirmada gera movimento `purchase_in`, aumenta estoque, recalcula custo medio e atualiza valor em estoque. Baixa por chave fica bloqueada ate integracao SEFAZ/certificado.

## 2026-06-16 - Motor inicial NFC-e SP com A1 e CSC

- Contexto: a area Fiscal ja armazenava certificado A1, CSC/ID e documentos fiscais, mas ainda marcava a assinatura/envio SEFAZ como etapa posterior.
- Decisao: criar o motor inicial de NFC-e para SP com validacao de cadastro fiscal/produtos, geracao de chave de acesso, XML 4.00, QR Code com CSC, assinatura A1 e chamada ao WebService `NFeAutorizacao4` da SEFAZ-SP em homologacao/producao conforme ambiente configurado.
- Consequencias: o documento fiscal so fica `authorized` quando a SEFAZ retornar autorizacao. Falhas de cadastro, certificado, transmissao ou rejeicoes da SEFAZ ficam gravadas no documento como `rejected`, com codigo e mensagem para correcao. A primeira etapa cobre NFC-e modelo 65 em SP; NF-e modelo 55, outros estados, cancelamento, inutilizacao e contingencia ficam como evolucoes posteriores.
- Alternativas consideradas: alterar estoque diretamente pelo cadastro do produto; rejeitado porque nao cria rastreabilidade, nao serve para XML e nao fecha custo medio profissional.

## 2026-06-06 - Arquitetura fiscal NFC-e/NF-e com A1 por empresa

- Status: aprovado para desenvolvimento incremental.
- Contexto: o Lynkar ERP/PDV sera vendido para empresas diferentes, com bancos separados por tenant. O PDV precisa atender padarias, mercados, lojas e assistencias tecnicas. Para novos clientes, o foco fiscal deve ser NFC-e/NF-e online com Certificado Digital A1 da empresa emissora, e nao SAT como caminho principal.
- Decisao: criar um modulo Fiscal separado de Vendas, PDV e Estoque. Cada empresa/tenant tera sua propria configuracao fiscal e seu proprio Certificado Digital A1. O CPF do consumidor no PDV sera opcional. A venda e o documento fiscal serao registros separados. SAT fica apenas como compatibilidade futura/legada, nao como foco principal.
- Consequencias: vendas e PDV continuam registrando venda, pagamento e baixa de estoque, mas XML, status SEFAZ, protocolo, chave de acesso, DANFE e envios ficam no modulo Fiscal. Emissao real para SEFAZ depende de etapa posterior de assinatura A1, webservices estaduais, homologacao e armazenamento seguro do certificado.
- Alternativas consideradas: manter SAT como fluxo principal; rejeitado porque nao atende melhor a escalabilidade nacional e a direcao atual do projeto. Gravar fiscal dentro da venda; rejeitado porque mistura documento comercial com documento fiscal e dificulta manutencao.

## 2026-06-06 - Armazenamento criptografado do Certificado Digital A1 por tenant

- Status: implementado como base local.
- Contexto: cada empresa cliente possui banco separado e precisa cadastrar seu proprio certificado A1 para PDV/NFC-e, NF-e e baixa futura de XML pela chave.
- Decisao: armazenar o arquivo `.pfx/.p12` e a senha criptografados no banco do proprio tenant, com metadados no modulo Fiscal. A API nao devolve o arquivo, senha ou chaves internas para o frontend; o app recebe apenas status, nome, hash SHA-256 e validade quando houver.
- Consequencias: o PDV e Entradas conseguem verificar se a empresa possui certificado antes de liberar fluxos fiscais. A comunicacao real com SEFAZ ainda precisa de homologacao, assinatura XML e bibliotecas fiscais especificas.
- Observacao de seguranca: em producao, a `SECRET_KEY` do ambiente precisa ser forte, unica por instalacao e guardada fora do codigo. Se a chave mudar, certificados criptografados com a chave antiga nao poderao ser descriptografados sem rotina de migracao.

## 2026-06-06 - Dashboard adaptativa por segmento e vitrine master

- Status: aprovado e implementado localmente.
- Contexto: empresas como padarias, mercados e lojas nao devem ver indicadores de assistencia tecnica, maquinas online/offline ou monitoramento quando esses modulos nao fazem parte do negocio contratado.
- Decisao: a API de dashboard passa a devolver `dashboard_kind`: `technical` para assistencia tecnica/monitoramento e `showcase` para demais empresas. A dashboard-vitrine e controlada pelo superadmin master em tabela global `dashboard_contents`, separando cards de Avisos, Certificados e Loja.
- Consequencias: tenants comerciais recebem uma area inicial de comunicados e oportunidades comerciais sem misturar dados operacionais entre empresas. O master pode publicar cards para todos, para um segmento ou para empresas com determinado modulo contratado. A oferta de certificado A1 some automaticamente quando o tenant ja possui certificado fiscal cadastrado.
- Alternativas consideradas: manter uma dashboard unica para todos; rejeitado porque exibiria dados sem sentido para padaria/mercado e reduziria qualidade do produto SaaS.

## 2026-06-06 - Upload publico de imagens para vitrine e estoque

- Status: aprovado e implementado localmente.
- Contexto: a Loja Lyncar, os avisos master e o estoque precisam exibir imagens cadastradas pelo usuario, sem depender apenas de URL externa.
- Decisao: criar upload de imagens validado pela API, salvar arquivos em pasta publica do servidor e gravar no banco apenas a URL publica. Imagens de Avisos/Certificados/Loja pertencem ao master; imagens de produtos pertencem ao banco do tenant.
- Consequencias: o frontend pode escolher foto local ou usar URL externa. As imagens sao tratadas como midia publica de produto/vitrine, nao como documento privado. O deploy precisa preservar a pasta de uploads/publicos entre atualizacoes.
- Alternativas consideradas: armazenar binario direto no banco; rejeitado para esta fase por aumentar peso do banco e dificultar cache/entrega web.

## 2026-06-08 - Separacao entre Caixa e Financeiro para crediario

- Status: aprovado e implementado localmente.
- Contexto: vendas crediario estavam aparecendo junto ao fechamento de caixa, mas em ERP o fechamento do turno deve conferir o caixa, enquanto crediario pertence ao contas a receber do cliente.
- Decisao: mover a gestao de crediario para o modulo Financeiro / Contas a Receber, agrupando por cliente e exibindo extrato de compras, itens vendidos, pagamentos e saldo. A tela Caixa fica somente para fechamento, tesouraria, divergencias, sangrias e suprimentos.
- Consequencias: PDV e Vendas continuam gerando contas a receber quando a forma de pagamento for crediario, mas a baixa parcial/total passa a ocorrer no Financeiro. Contas a Pagar fica preparado como area separada para fornecedores e entradas de mercadoria.
- Alternativas consideradas: manter crediario no fechamento de caixa; rejeitado porque mistura conferencia de turno com cobranca/crediario e nao mostra a divida consolidada do cliente.

## 2026-06-08 - Baixa por cliente com alocacao automatica

- Status: aceita.
- Contexto: o cliente pode voltar para acertar uma parte da divida total, nao necessariamente uma compra especifica.
- Decisao: manter baixa individual por titulo e adicionar recebimento por cliente. O recebimento por cliente distribui o valor automaticamente nos titulos vencidos/mais antigos primeiro.
- Consequencias: o Financeiro passa a suportar operacao mais parecida com ERP profissional: extrato consolidado do cliente, baixa parcial, baixa total, historico de pagamentos e saldo remanescente por titulo.
- Alternativas consideradas: obrigar o usuario a escolher manualmente cada compra; rejeitado porque deixa o caixa financeiro lento quando o cliente paga um valor parcial geral.

## 2026-06-08 - Padronizacao visual ERP no Flutter

- Status: aprovado e implementado localmente.
- Contexto: o app administrativo precisava ganhar aparencia mais profissional de ERP sem criar funcionalidades novas.
- Decisao: centralizar o acabamento visual no tema global do Flutter, no `AppCard` e no menu lateral, adicionando dependencias leves `google_fonts`, `flutter_animate` e `gap`.
- Consequencias: telas existentes passam a herdar tipografia, inputs, botoes, tabelas, cards e navegacao lateral com visual mais consistente. Mudancas futuras de identidade devem priorizar o tema global antes de mexer tela por tela.
- Alternativas consideradas: redesenhar cada tela isoladamente; rejeitado nesta etapa porque aumentaria risco de regressao e duplicacao visual.

## 2026-06-13 - Toda alteracao local precisa virar atualizacao de servidor

- Status: aprovado.
- Contexto: o sistema esta sendo ajustado localmente e o servidor de producao possui dados, dominios, IP, Cloudflare e configuracoes proprias.
- Decisao: a partir de 13/06/2026, toda alteracao feita daqui para frente deve ser tratada como candidata a atualizacao do servidor. Ao finalizar uma mudanca, gerar pacote/roteiro de atualizacao no HD externo quando solicitado e avaliar se existe impacto de banco.
- Consequencias: mudancas somente de frontend podem ser enviadas como pacote parcial com arquivos alterados e build web. Mudancas de backend ou modelo de dados precisam listar migracoes necessarias e cuidados para preservar dados reais do servidor. Nunca restaurar dados locais por cima dos dados de producao sem autorizacao explicita.
- Observacao: banco, uploads/fotos, `.env`, IP, dominio e Cloudflare do servidor devem ser preservados/configurados no proprio servidor.

## 2026-06-13 - Fechamento de caixa considera dinheiro liquido apos troco

- Status: aprovado e implementado localmente.
- Contexto: no PDV, quando uma venda de R$ 3,00 era paga com R$ 5,00 em dinheiro e R$ 2,00 de troco, o fechamento esperava R$ 5,00 no caixa. Na operacao real, o caixa fica apenas com R$ 3,00 da venda, pois o troco saiu da gaveta.
- Decisao: para fechamento de caixa, o total da forma `dinheiro` deve guardar o valor liquido que ficou no caixa: dinheiro recebido menos troco. A venda continua registrando valor recebido bruto e troco separadamente para auditoria/comprovante.
- Consequencias: o fundo inicial continua fora do fechamento; sangrias continuam abatendo; divergencia passa a comparar a contagem contra o dinheiro real do movimento. Atualizacoes do servidor precisam substituir o frontend web e a rota backend de vendas administrativas. Nao ha migracao de banco.

## 2026-06-13 - Sessao do site expira apos 30 minutos de inatividade real

- Status: aprovado e implementado localmente.
- Contexto: o site podia deslogar durante uso porque a atividade era registrada apenas em alguns eventos e o tempo de inatividade estava em 10 minutos. A regra de inatividade e desejada apenas para o site, nao para apps Android/iOS/Windows.
- Decisao: alterar o timeout de inatividade do site para 30 minutos e registrar atividade por clique, toque, movimento/hover do mouse, scroll e teclado. Apps nao usam regra de inatividade local; continuam sujeitos apenas a expiracao tecnica do token.
- Consequencias: o usuario do site nao deve cair enquanto estiver interagindo com a tela. Atualizacao do servidor deve incluir `admin_app/admin_flutter/lib/app.dart` e novo build web. Nao ha migracao de banco.

## 2026-06-13 - Permissoes separam PDV de historico de vendas

- Status: aprovado e implementado localmente.
- Contexto: ao liberar somente PDV para um usuario, o botao Vendas tambem podia aparecer porque o acesso de caixa herdava `sales:view`. O objetivo operacional e permitir perfil so para abrir o PDV e vender, sem acesso ao historico/listagem de vendas.
- Decisao: `sales:create` passa a representar Operar PDV e pertence ao modulo `pdv`; `sales:view` continua no modulo `sales` e representa Ver vendas/historico. O menu lateral deve mostrar PDV com `sales:create` e Vendas com `sales:view`. O papel padrao Operador de caixa deixa de receber `sales:view`.
- Consequencias: o master consegue liberar modulo PDV separado do historico de vendas, e o cliente consegue criar perfil "Somente PDV" sem puxar o botao Vendas. Atualizacao do servidor precisa rodar a rotina local de migracao/seed de permissoes (`python -m app.migrate_local`) em cada tenant aplicavel, pois houve mudanca de modulo/rotulo/permissoes padrao. Nao ha alteracao de schema.

## 2026-06-13 - Abertura de caixa do PDV estabilizada no Flutter Web

- Status: aprovado e implementado localmente.
- Contexto: apos digitar fiscal/operador para abrir o caixa, o Flutter Web podia exibir tela vermelha de assert em modo debug ou tela branca por instabilidade do ciclo de dialogs/estado. O PDV tambem deve preservar a regra antiga de nao encerrar sessao enquanto houver caixa aberto.
- Decisao: remover o listener global de notificacoes de scroll da camada de sessao e manter atividade por clique, toque, movimento/hover, roda do mouse e teclado. No fluxo de autorizacao fiscal/abertura de caixa, separar o fechamento do dialog da atualizacao do estado do PDV com um pequeno yield seguro.
- Consequencias: a abertura de caixa fica mais estavel no site e a sessao continua sendo renovada quando existe caixa aberto. Atualizacao do servidor precisa publicar novo build web e incluir `admin_app/admin_flutter/lib/app.dart` e `admin_app/admin_flutter/lib/screens/pdv_screen.dart`. Nao ha migracao de banco adicional alem da seed de permissoes ja prevista.

## 2026-06-13 - Perfis de acesso precisam explicar o que cada permissao libera

- Status: aprovado e implementado localmente.
- Contexto: a tela de perfis possui muitos modulos e permissoes, dificultando criar um usuario simples, como somente PDV, principalmente no servidor.
- Decisao: adicionar explicacoes praticas na tela de perfis: receita rapida para somente PDV, alerta para evitar "Liberar tudo" em acesso limitado, dica por modulo e dica por permissao. Criar tambem um guia em `E:\GUIA_PERMISSOES_LYNCAR_PDV_E_MODULOS_2026-06-13.md`.
- Consequencias: o cliente consegue entender que PDV e Vendas sao acessos diferentes: `sales:create` mostra PDV/operacao de caixa e `sales:view` mostra historico/listagem de vendas. Atualizacao do servidor precisa publicar novo build web e incluir `admin_app/admin_flutter/lib/screens/settings_screen.dart`.

## 2026-06-14 - Contratos variaveis sao faturamento recorrente por apontamento

- Status: em implementacao local.
- Contexto: a cliente de cafe da manha cobra empresas por pessoa e por dias realmente atendidos na quinzena, com excecoes para sabado, domingo e feriado.
- Decisao: tratar como modulo proprio `service_contracts`, liberado pelo master e disponivel somente a partir do plano Pro. Nao usar mensalidade fixa simples. O contrato define regras, o calendario/feriado define o tipo de dia, o apontamento confirma o ocorrido, a baixa de produtos acontece no apontamento e o fechamento gera contas a receber.
- Consequencias: o deploy no servidor precisa criar novas tabelas de contratos, regras, feriados, apontamentos, itens consumidos e faturamentos. Confirmar apontamento gera movimento de estoque; cancelar apontamento estorna. Mudancas em produtos/quantidades apos baixa estornam automaticamente a baixa anterior e exigem nova confirmacao do apontamento para preservar rastreabilidade.
- Alternativas consideradas: gerar uma mensalidade fixa no contas a receber; rejeitado porque nao reflete dias atendidos, feriados nem consumo real de produtos.

## 2026-06-14 - PDV Windows usa entrypoint separado

- Status: em implementacao local.
- Contexto: o PDV do site deve continuar funcional e nao deve ser transformado visualmente no modelo do app Windows.
- Decisao: manter o fluxo compartilhado de negocio do PDV, mas ativar um modo visual proprio somente pelo entrypoint `main_pdv.dart`. O app Windows nao deve exibir login operacional; deve usar configuracao local do terminal com servidor API, empresa, usuario tecnico e senha. O build Windows usa `flutter build windows -t lib/main_pdv.dart`, gerando `lyncar_pdv.exe`.
- Consequencias: ajustes visuais especificos do app Windows devem ser controlados por parametros/modo proprio para nao afetar o PDV web. O instalador/atalho do caixa deve apontar para `lyncar_pdv.exe`. Cada terminal fica vinculado a uma empresa (`company_code`); o token retornado pelo login tecnico faz o backend selecionar o banco tenant correto, evitando mistura entre empresas. A empresa `master` nao pode ser usada como empresa do terminal PDV. Fiscal e operador continuam sendo informados na abertura do caixa. A tela fechada do Windows deve ficar minimalista, mostrando somente `CAIXA FECHADO`; Enter permanece como atalho operacional silencioso.
- Alternativas consideradas: criar outro projeto Flutter separado agora; adiado para evitar duplicar regras de venda, pagamento, caixa e autorizacao fiscal nesta fase.

## 2026-06-14 - Pacotes de servidor devem ser separados por escopo enviado

- Status: aprovado.
- Contexto: o pacote antigo do HD externo ja foi enviado ao servidor, mas ele nao continha o modulo de Contratos variaveis.
- Decisao: apagar do E: o pacote antigo ja enviado e gerar um novo pacote somente com o que faltava, neste caso `ATUALIZACAO_PAPEZZOSYNC_CONTRATOS_VARIAVEIS_2026-06-14_22-45-27`.
- Consequencias: o servidor nao deve receber novamente alteracoes antigas desnecessarias. Para Contratos variaveis, o pacote leva fontes, build web e roteiro de migracao, sem dados locais. Toda atualizacao futura deve repetir essa separacao: identificar o que ja foi enviado, empacotar apenas o pendente e listar se ha impacto de banco.

## 2026-06-16 - Sistema local fica no D e pacotes de servidor ficam no E

- Status: aprovado.
- Contexto: houve confusao entre o volume `D:`, onde esta a area de teste/trabalho do ERP-PAPEZZOSYNC, e o volume `E:`, que e um HD externo usado para levar atualizacoes ao servidor.
- Decisao: tratar `D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\01_SISTEMA_COMPLETO\ERP-PAPEZZOSYNC` como raiz principal do sistema local/de teste. Tratar `D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\03_CEREBRO_OBSIDIAN\CEREBRO` como Vault/CEREBRO. Tratar `E:\` somente como destino/origem de pacotes de atualizacao para servidor, como `E:\ATUALIZACAO_PAPEZZOSYNC_*`.
- Consequencias: antes de estudar ou alterar codigo, usar a base do `D:`. Antes de enviar para producao, gerar pacote no `E:` com somente o escopo necessario, preservando banco real, uploads, `.env`, IP, dominio e Cloudflare do servidor. Nao assumir que o pacote do `E:` contem a feature inteira; ele pode ser incremental.

## 2026-06-16 - Feriados dos contratos sincronizam automaticamente

- Status: aprovado e implementado localmente.
- Contexto: a regra de feriado em Contratos variaveis existia, mas dependia de cadastro previo na tabela `holidays`. Isso tornava a opcao feriado pouco util na operacao real.
- Decisao: antes de gerar apontamentos ou fechar quinzena, o backend sincroniza feriados do ano do periodo. Feriados nacionais usam BrasilAPI sem chave. Feriados municipais/estaduais usam FeriadosAPI quando `FERIADOS_API_TOKEN` estiver configurado, resolvendo o codigo IBGE pela API de localidades do IBGE com base em cidade/UF do cliente. Falhas de rede/API nao bloqueiam a operacao; o sistema usa o que ja estiver salvo no banco.
- Consequencias: o usuario nao precisa clicar em atualizar feriados. O servidor precisa ter acesso de internet para sincronizar automaticamente e, para municipais/estaduais completos, precisa de token da FeriadosAPI no `.env`. Sem token, a automacao cobre os feriados nacionais e preserva o cadastro manual como complemento.

## 2026-06-16 - Site comercial lyncar.com.br fica separado do ERP

- Status: implementado localmente para teste.
- Contexto: o ERP administrativo continua usando `http://127.0.0.1:5000/`, mas tambem e necessario um site publico bonito e funcional para `lyncar.com.br`, com planos e solicitacao por WhatsApp ou email.
- Decisao: manter o site comercial em projeto Flutter separado em `C:\Users\vpape\Documents\lyncarsite`, usando assets reais da marca, `google_fonts` e `url_launcher`. Para teste local, servir o build web em `http://127.0.0.1:5050/`, sem conflitar com a porta 5000 do ERP.
- Consequencias: ajustes de landing page, planos e chamadas comerciais devem ser feitos no projeto `lyncarsite`. Deploy do dominio `lyncar.com.br` deve publicar o conteudo de `build\web` desse projeto, nao o build administrativo do ERP. A marca Lyncar representa o sistema/produto; a marca PS deve aparecer como desenvolvedora/assinatura. Os valores publicos dos planos seguem os defaults cadastrados no backend: Start R$ 59,90/mes, Pro R$ 119,90/mes e Business R$ 279,90/mes.

## 2026-06-16 - Pacotes do E separados entre ERP e site publico

- Status: aprovado e gerado localmente.
- Contexto: o pacote antigo de Contratos variaveis que estava no `E:` ainda nao foi enviado ao servidor, e o site publico `lyncar.com.br` tambem passou a ter build proprio.
- Decisao: apagar o pacote antigo do `E:` e gerar dois pacotes separados: `ATUALIZACAO_PAPEZZOSYNC_CONTRATOS_VARIAVEIS_2026-06-16_12-07-11` para o ERP administrativo, e `SITE_LYNCAR_COM_BR_2026-06-16_12-07-11` para o site publico. Cada pacote possui seu proprio `LEIA_PRIMEIRO` e zip.
- Consequencias: no servidor, o pacote de Contratos deve ser aplicado sobre o projeto ERP-PAPEZZOSYNC e seu build administrativo. O pacote do site deve ser publicado no dominio publico `lyncar.com.br`. Nao misturar os dois builds. O site comercial nao deve oferecer Monitoramento, pois esse recurso fica exclusivo da assistencia tecnica interna por enquanto.

## 2026-06-18 - Fiscal do PDV independente e recebimento orientado por fila

- Status: aprovado e implementado localmente.
- Contexto: a empresa pode possuir Certificado A1, mas ainda nao ter todos os dados fiscais obrigatorios dos produtos prontos para emitir NFC-e. Ao mesmo tempo, Entradas ja possuia XML, chave, planilha, entrada manual e coletor, mas iniciava pelo formulario em vez da fila operacional.
- Decisao: separar a habilitacao geral de NFC-e do uso automatico no PDV pelo campo `pdv_nfce_enabled`, com padrao desligado. Reorganizar Entradas como Central de recebimentos: pesquisa/lista primeiro, criacao/importacao como acao secundaria e escolha entre conferencia no computador ou coletor. Uma entrada aberta e atualizada no mesmo registro; estoque so movimenta na finalizacao.
- Consequencias: a cliente pode operar o caixa comercial sem risco de tentativa fiscal prematura e ativar a emissao depois. O recebimento ganha rastreabilidade, evita entradas duplicadas e preserva a conferencia cega do coletor com decisao final no computador. O deploy exige migracao do novo campo fiscal e publicacao coordenada de backend e frontend.
- Alternativas consideradas: desligar o modulo Fiscal inteiro; rejeitado porque impediria manter certificado e configuracoes preparados. Criar uma entrada nova ao abrir a nota no computador; rejeitado porque duplicaria documento, itens e recebimento.

## 2026-06-18 - Caixa de XML central no transporte e isolada por tenant

- Status: aprovado e implementado localmente.
- Contexto: fornecedores devem poder enviar XML automaticamente, mas o master nao deve acessar documentos fiscais dos clientes e um endereco de e-mail nao pode ser considerado prova de que a nota pertence ao tenant.
- Decisao: guardar no master somente token/endereco de roteamento. Guardar mensagem, XML e entrada no banco tenant. Validar obrigatoriamente o CNPJ do destinatario da NF-e contra o cadastro fiscal antes de persistir o XML. Rejeicoes por CNPJ guardam somente metadados sanitizados.
- Consequencias: cada cliente possui sua Caixa de XML, o master nao acessa o conteudo e notas de outra empresa nao atravessam o isolamento. A infraestrutura de producao precisa de dominio de entrada, MX/provedor e segredo de webhook.
- Alternativas consideradas: uma caixa unica visivel ao master; rejeitada por privacidade, LGPD e risco operacional. Confiar apenas no alias de destino; rejeitado porque enderecos podem ser encaminhados ou usados incorretamente.

## 2026-06-18 - Venda sem NFC-e gera cupom comercial nao fiscal

- Status: aprovado e implementado localmente.
- Contexto: o controle Fiscal no PDV pode ficar desligado enquanto a empresa completa o cadastro tributario, mas o consumidor ainda precisa receber um comprovante da compra.
- Decisao: toda venda do PDV gera comprovante. Quando a emissao fiscal estiver efetivamente disponivel, segue NFC-e. Caso contrario, o frontend gera cupom termico claramente marcado como nao fiscal.
- Consequencias: a operacao comercial continua completa sem sugerir autorizacao fiscal inexistente. O cupom nao fiscal nao substitui NFC-e e nao inclui elementos SEFAZ. No web, o navegador abre o dialogo de impressao automaticamente. No app Windows, o comprovante texto e enviado para a impressora padrao configurada no sistema.

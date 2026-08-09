# Funcionalidades Implementadas

Registrar funcionalidades ja implementadas e validadas no projeto.

## Indice

- PDV com operadores, fiscais e modo focado.
- Conferencia de fechamento de caixa.
- Estoque com ficha tecnica/composicao.
- Ordem de producao com ciclo completo e baixa automatica de insumos.
- Saldo por lote e validade no estoque.
- Dashboard-vitrine controlada pelo master.
- Financeiro com contas a receber por cliente.
- Contas a pagar com fornecedores, entradas e despesas avulsas.
- Entradas de mercadoria com XML, planilha e cadastro em massa.
- Recebimento mobile com leitura de codigo de barras.
- Modulo de Relatorios gerenciais.
- Vendedor responsavel em Vendas e PDV.
- Area de Configuracoes com modulo Fiscal.
- Notas fiscais com NF-e 55, NFC-e 65, DANFE e cancelamento SEFAZ real.

## Notas fiscais com NF-e 55, NFC-e 65, DANFE e cancelamento SEFAZ real

- Modulo afetado: [[08 - Modulos do Sistema/Fiscal|Fiscal / Notas fiscais]].
- Objetivo: separar configuracao fiscal da operacao diaria e permitir emissao, consulta, impressao e cancelamento fiscal real.
- Comportamento esperado:
  - `Configuracoes > Fiscal` guarda certificado A1, CSC/ID, series, numeracao e cadastro tributario.
  - `Notas fiscais` no menu lateral lista documentos emitidos, status, ambiente, venda vinculada, chave/protocolo e mensagens da SEFAZ.
  - Usuario pode preparar e emitir NFC-e modelo 65 e NF-e modelo 55 em homologacao SP.
  - DANFE NF-e e DANFE NFC-e sao gerados em PDF e enviados para impressao pelo navegador.
  - Cancelamento chama evento SEFAZ `110111`; status local so muda para cancelado quando a SEFAZ aceita.
  - Rejeicao de cancelamento mantem o documento autorizado e mostra a mensagem de retorno.
- Backend envolvido:
  - `backend/app/api/routes/fiscal.py`
  - `backend/app/services/nfce_sp.py`
  - `backend/app/services/nfe_sp.py`
  - `backend/app/services/fiscal_events_sp.py`
  - `backend/app/services/fiscal_pdf.py`
  - `backend/app/models/fiscal.py`
  - `backend/app/schemas/fiscal.py`
  - `backend/app/migrate_local.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/fiscal_screen.dart`
  - `admin_app/admin_flutter/lib/screens/fiscal_documents_screen.dart`
  - `admin_app/admin_flutter/lib/services/fiscal_print.dart`
  - `admin_app/admin_flutter/lib/services/fiscal_print_web.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
- Banco de dados envolvido:
  - `company_fiscal_settings`.
  - `fiscal_documents`.
- Validacao feita em homologacao:
  - NF-e 55 autorizada: venda `V35`, documento `30`, numero `1`, chave `35260663816719000115550010000000011054393258`, protocolo `135260005946781`, `cStat=100`.
  - Cancelamento da NF-e aceito: protocolo `135260005946817`, `cStat=135`.
  - NFC-e fresca autorizada e cancelada: venda `V31`, documento `31`, numero `14`, cancelamento aceito com `cStat=135`.
  - NFC-e antiga rejeitada por prazo (`cStat=501`) permaneceu autorizada, confirmando que nao ha cancelamento falso no banco.
- Como validar:
  - Configurar certificado A1 e dados fiscais da empresa.
  - Garantir cliente/produtos com dados fiscais obrigatorios.
  - Criar venda finalizada.
  - Abrir Notas fiscais, preparar NF-e ou NFC-e e emitir.
  - Abrir detalhes, imprimir DANFE e cancelar dentro do prazo permitido.

## PDV com operadores, fiscais e modo focado

- Modulo afetado: [[08 - Modulos do Sistema/PDV|PDV]].
- Objetivo: permitir operacao de caixa com operador separado do usuario do ERP e autorizacoes de fiscal/supervisor.
- Comportamento esperado:
  - O caixa abre com codigo e senha/PIN de operador.
  - Sangria e cancelamento solicitam autorizacao de fiscal/supervisor.
  - O PDV possui modo focado/tela cheia dentro do app.
  - O app nao encerra a sessao por inatividade enquanto o caixa esta aberto.
- Backend envolvido:
  - `backend/app/api/routes/pdv_operators.py`
  - `backend/app/models/pdv_operator.py`
  - `backend/app/schemas/pdv_operator.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/sales_screen.dart`
  - `admin_app/admin_flutter/lib/screens/pdv_operators_screen.dart`
  - `admin_app/admin_flutter/lib/app.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
- Banco de dados envolvido:
  - `pdv_operators`.
- Como validar:
  - Cadastrar operador/fiscal em Op. PDV.
  - Abrir PDV com codigo e senha/PIN de operador.
  - Acionar Tela cheia.
  - Registrar sangria e confirmar que pede codigo de fiscal.
  - Deixar caixa aberto e confirmar que a sessao nao cai por inatividade.

## Conferencia de fechamento de caixa

- Modulo afetado: [[08 - Modulos do Sistema/PDV|PDV / Caixa]].
- Objetivo: permitir que fechamentos enviados pelo PDV sejam conferidos pela tesouraria antes de serem considerados finalizados.
- Comportamento esperado:
  - O PDV registra fechamento com fundo inicial, vendas, pagamentos, sangrias/suprimentos, dinheiro esperado, dinheiro contado e observacao.
  - A tela Caixa lista fechamentos pendentes, divergentes e total fechado.
  - Cada fechamento pode ser aberto para detalhar formas de pagamento, movimentos e resumo do dinheiro.
  - Usuario com permissao `pdv_operators:manage` pode aprovar ou marcar divergencia com observacao.
- Backend envolvido:
  - `backend/app/models/cash_closing.py`
  - `backend/app/schemas/cash_closing.py`
  - `backend/app/api/routes/cash_closings.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/cash_closing.dart`
  - `admin_app/admin_flutter/lib/screens/cash_closings_screen.dart`
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
- Banco de dados envolvido:
  - `cash_closings`
  - `cash_closing_payments`
  - `cash_closing_movements`
- Como validar:
  - Abrir caixa no PDV.
  - Fazer venda.
  - Fechar caixa informando dinheiro contado.
  - Abrir Caixa, clicar no fechamento e aprovar ou marcar divergencia.

## Estoque com ficha tecnica/composicao

- Modulo afetado: [[08 - Modulos do Sistema/Produtos e Servicos|Estoque / Produtos e Servicos]].
- Objetivo: preparar o ERP para padarias, mercados, lojas e negocios com producao propria.
- Comportamento esperado:
  - O menu passa a exibir **Estoque** em vez de Produtos.
  - O cadastro aceita tipos como produto acabado, mercadoria/revenda, materia-prima, embalagem, peca, servico e insumo.
  - Cada produto pode abrir a tela de ficha tecnica/composicao.
  - A ficha tecnica lista componentes, quantidade, unidade, perda percentual e custo estimado.
  - A futura ordem de producao usara essa composicao para dar entrada no produto final e baixa nas materias-primas.
- Backend envolvido:
  - `backend/app/models/product_composition.py`
  - `backend/app/schemas/product_composition.py`
  - `backend/app/api/routes/products.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/products_screen.dart`
  - `admin_app/admin_flutter/lib/models/product_composition.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
- Banco de dados envolvido:
  - `product_composition_items`.
- Como validar:
  - Cadastrar uma materia-prima, por exemplo Farinha.
  - Cadastrar um produto acabado, por exemplo Pao Frances.
  - Abrir a ficha tecnica do produto acabado.
  - Adicionar a materia-prima com quantidade, unidade e perda.
  - Confirmar que o custo estimado aparece quando o componente possui custo cadastrado.

## Ordem de producao com ciclo completo e baixa automatica de insumos

- Modulo afetado: [[08 - Modulos do Sistema/Produtos e Servicos|Estoque / Producao]].
- Objetivo: permitir fabricar produtos acabados a partir da ficha tecnica.
- Comportamento esperado:
  - A tela Producao permite criar OP planejada com produto, quantidade, previsao e observacao.
  - A previa da ficha tecnica e calculada pelo backend, respeitando conversao de unidades, perda, custo medio e estoque disponivel.
  - A OP pode ser iniciada, concluida ou cancelada.
  - Criar OP nao movimenta estoque.
  - Ao concluir, entra estoque do produto acabado.
  - Ao mesmo tempo, baixa estoque das materias-primas, insumos e embalagens pelos lotes disponiveis.
  - Ao cancelar uma OP concluida, o sistema estorna produto acabado e devolve componentes quando o produto acabado ainda possui saldo.
  - Os movimentos aparecem no historico de estoque como `production_in` e `production_consumption`.
  - Estornos aparecem como `production_cancel_out` e `production_cancel_return`.
- Backend envolvido:
  - `backend/app/models/production_order.py`
  - `backend/app/schemas/production_order.py`
  - `backend/app/api/routes/production_orders.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/production_orders_screen.dart`
  - `admin_app/admin_flutter/lib/models/production_order.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
- Banco de dados envolvido:
  - `production_orders`.
  - `production_order_components`.
  - `stock_movements`.
  - `product_batches`.
- Como validar:
  - Cadastrar materia-prima com estoque.
  - Cadastrar produto acabado.
  - Montar ficha tecnica do produto acabado.
  - Criar OP planejada e conferir previa de componentes.
  - Iniciar OP.
  - Concluir OP e confirmar entrada do produto acabado e baixa dos componentes no historico.
  - Cancelar OP concluida e confirmar estorno quando houver saldo do produto acabado.

## Saldo por lote e validade no estoque

- Modulo afetado: [[08 - Modulos do Sistema/Produtos e Servicos|Estoque]].
- Objetivo: controlar produtos com lote e validade por saldo individual, essencial para mercados, padarias, alimentos, farmacia, cosmeticos e itens rastreaveis.
- Comportamento esperado:
  - Entrada de mercadoria aceita cria ou soma saldo do lote.
  - A listagem de estoque mostra a proxima validade/lote com saldo.
  - Cada produto tem botao para consultar saldos por lote.
  - Venda/PDV e consumo de producao baixam saldo do lote que vence primeiro.
  - Cancelamento de venda devolve saldo para lote de retorno quando o lote original nao estiver rastreado no documento da venda.
- Backend envolvido:
  - `backend/app/models/product_batch.py`
  - `backend/app/services/product_batches.py`
  - `backend/app/api/routes/products.py`
  - `backend/app/api/routes/stock_entries.py`
  - `backend/app/api/routes/sales.py`
  - `backend/app/api/routes/production_orders.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/product_batch.dart`
  - `admin_app/admin_flutter/lib/screens/products_screen.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
- Banco de dados envolvido:
  - `product_batches`.
- Como validar:
  - Confirmar uma entrada com lote e validade.
  - Abrir Estoque e conferir coluna Validade/Lote.
  - Clicar em Saldos por lote e confirmar saldo, fornecedor e NF.
  - Fazer uma venda/PDV e verificar baixa no lote.
  - Fazer producao usando materia-prima com lote e confirmar baixa do lote.

## Dashboard-vitrine controlada pelo master

- Modulo afetado: Dashboard / Master SaaS.
- Objetivo: mostrar dashboards diferentes conforme o tipo de empresa, evitando que padarias, mercados e lojas vejam informacoes de assistencia tecnica.
- Comportamento esperado:
  - Empresas de assistencia tecnica ou com monitoramento veem a dashboard operacional de maquinas/chamados.
  - Empresas comerciais sem modulos tecnicos veem uma vitrine separada em Avisos, Certificado Digital A1 e Loja Lyncar.
  - O painel master possui menus separados Avisos, Certificados e Loja para criar, editar e excluir cards.
  - A area de certificado A1 nao aparece quando o tenant ja possui certificado fiscal cadastrado.
  - A Loja aceita produtos proprios, links afiliados e links externos/WhatsApp.
  - Avisos, certificados e cards da Loja podem receber imagem enviada pelo master ou URL externa.
  - Cards podem ser exibidos para todos, por segmento ou por modulo contratado.
- Backend envolvido:
  - `backend/app/models/dashboard_content.py`
  - `backend/app/schemas/dashboard.py`
  - `backend/app/schemas/dashboard_content.py`
  - `backend/app/api/routes/dashboard.py`
  - `backend/app/api/routes/master_dashboard.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/dashboard_summary.dart`
  - `admin_app/admin_flutter/lib/screens/dashboard_screen.dart`
  - `admin_app/admin_flutter/lib/screens/dashboard_contents_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
- Banco de dados envolvido:
  - `dashboard_contents` no banco master.
- Como validar:
  - Logar como master e abrir Vitrine.
  - Cadastrar um card ativo para `todos` ou para o segmento/modulo desejado.
  - Logar em uma empresa sem monitoramento e confirmar que a dashboard mostra a vitrine.
  - Logar em empresa com monitoramento e confirmar que a dashboard tecnica continua aparecendo.

## Imagens no estoque e na vitrine

- Modulo afetado: Estoque / Dashboard-vitrine / Master SaaS.
- Objetivo: permitir cadastrar fotos de produtos e imagens comerciais em avisos, certificados e loja.
- Comportamento esperado:
  - O cadastro de estoque possui seletor de foto do produto.
  - A listagem de estoque exibe miniatura quando o produto tem imagem.
  - O master pode enviar imagem nos cards de Avisos, Certificados e Loja.
  - Cards da vitrine exibem miniatura quando houver imagem e continuam com icone quando nao houver.
  - Somente imagens JPG, PNG, WEBP ou GIF de ate 5 MB devem ser aceitas.
- Backend envolvido:
  - `backend/app/api/routes/uploads.py`
  - `backend/app/services/uploads.py`
  - `backend/app/models/product.py`
  - `backend/app/schemas/product.py`
  - `backend/app/migrate_local.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/models/product.dart`
  - `admin_app/admin_flutter/lib/screens/products_screen.dart`
  - `admin_app/admin_flutter/lib/screens/dashboard_contents_screen.dart`
  - `admin_app/admin_flutter/lib/screens/dashboard_screen.dart`
- Banco de dados envolvido:
  - Campo `products.image_url` no banco de cada tenant.
  - Campo `dashboard_contents.image_url` no banco master.
- Como validar:
  - Cadastrar/editar produto com foto e conferir miniatura no Estoque.
  - Como master, cadastrar card de aviso ou loja com foto e conferir exibicao na dashboard-vitrine de um tenant comercial.

## Busca e filtros avancados nas listas

- Modulo afetado: Estoque / Clientes / Vendas / Caixa / Entradas / Master SaaS.
- Objetivo: facilitar operacao com muitos registros, evitando que o usuario precise procurar manualmente em listas grandes.
- Comportamento esperado:
  - Estoque permite buscar por produto, codigo, codigo de barras, NCM, lote/validade e filtrar por tipo, status, valor, estoque baixo e itens com lote.
  - Clientes permite buscar por nome, documento, e-mail, telefone, contato, cidade e filtrar por PF/PJ, contrato e status.
  - Vendas permite buscar por numero, cliente, CPF, produto e forma de pagamento, alem de filtrar por status, origem e periodo.
  - Caixa permite buscar por fechamento, operador, status e observacao, alem de filtrar por status e divergencias.
  - Entradas permite buscar por fornecedor, documento, NF, chave, produto e lote, alem de filtrar por origem.
  - Conteudos master de avisos, certificados e loja permitem buscar por titulo/texto/link e filtrar por status.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/products_screen.dart`
  - `admin_app/admin_flutter/lib/screens/clients_screen.dart`
  - `admin_app/admin_flutter/lib/screens/sales_screen.dart`
  - `admin_app/admin_flutter/lib/screens/cash_closings_screen.dart`
  - `admin_app/admin_flutter/lib/screens/stock_entries_screen.dart`
  - `admin_app/admin_flutter/lib/screens/dashboard_contents_screen.dart`
- Banco de dados envolvido:
  - Sem alteracao de schema; filtros aplicados no frontend sobre dados carregados pela API.
- Como validar:
  - Abrir cada tela afetada.
  - Digitar parte do nome/codigo/documento e confirmar que a lista filtra.
  - Abrir filtros avancados quando existir e combinar status, tipo, periodo ou origem.
  - Limpar filtros e confirmar que a lista completa volta a aparecer.

## Cadastro de fornecedores integrado a entradas

- Modulo afetado: Fornecedores / Entradas / Estoque.
- Objetivo: tratar fornecedores como cadastro proprio do ERP e vincular compras/Notas de Entrada ao fornecedor correto.
- Comportamento esperado:
  - Menu Fornecedores permite buscar, cadastrar e editar fornecedor por tenant.
  - Fornecedor possui razao social/nome, fantasia, CNPJ/CPF, inscricao estadual, telefone, e-mail, endereco, cidade, UF, observacoes e status.
  - Entradas de mercadoria continuam aceitando entrada manual, importacao de NF-e por XML, planilha e chave NF-e futura.
  - Ao ler XML NF-e, o sistema usa o CNPJ/CPF do emitente para localizar fornecedor cadastrado.
  - Se encontrar fornecedor, a entrada seleciona automaticamente o cadastro.
  - Se nao encontrar, a tela avisa e permite cadastrar o fornecedor antes de confirmar a entrada.
  - Ao confirmar entrada, o registro guarda `supplier_id` quando houver cadastro e tambem snapshot de nome/documento do fornecedor.
- Backend envolvido:
  - `backend/app/models/supplier.py`
  - `backend/app/schemas/supplier.py`
  - `backend/app/schemas/stock_entry.py`
  - `backend/app/api/routes/stock_entries.py`
  - `backend/app/core/permissions.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/supplier.dart`
  - `admin_app/admin_flutter/lib/models/stock_entry.dart`
  - `admin_app/admin_flutter/lib/screens/suppliers_screen.dart`
  - `admin_app/admin_flutter/lib/screens/stock_entries_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/screens/users_screen.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
- Banco de dados envolvido:
  - `suppliers`.
  - `stock_entries.supplier_id`, `supplier_name`, `supplier_document`.
- Como validar:
  - Cadastrar fornecedor em Fornecedores.
  - Importar XML de entrada com o mesmo CNPJ e confirmar selecao automatica.
  - Importar XML com CNPJ novo e confirmar que a tela pede cadastro/vinculo.
  - Confirmar entrada e verificar historico em Entradas e Estoque.

## Entradas de mercadoria com XML, planilha e cadastro em massa

- Modulo afetado: Entradas / Estoque / Fornecedores.
- Objetivo: transformar a tela de entrada em fluxo operacional de ERP e facilitar primeira carga de produtos.
- Comportamento esperado:
  - A tela mostra indicadores de recebimentos, itens em conferencia, pendencias e valor recente.
  - Os fluxos ficam separados em abas: Recebimento manual, Importar NF-e (XML), Planilha de entrada e Chave NF-e.
  - O termo visual `XML gratis` nao deve ser usado; a importacao por arquivo deve aparecer como Importar NF-e (XML).
  - A aba Planilha de entrada permite baixar `modelo_entrada_mercadorias.xlsx`, ja formatado para Excel.
  - CNPJ/CPF, chave NF-e, codigo interno, codigo de barras, NCM e CFOP ficam como texto para evitar notacao cientifica.
  - A planilha permite informar fornecedor, NF, codigo interno, codigo de barras, produto, unidade, quantidade, custo, preco de venda, estoque minimo, categoria, marca, NCM, CFOP, lote, validade e observacao.
  - Ao importar planilha, o sistema vincula produtos por codigo interno/codigo de barras.
  - Se o produto nao existir e o usuario tiver permissao, o produto e cadastrado antes da conferencia.
  - Itens sem produto ficam pendentes para vinculo/conferencia e nao movimentam estoque ate serem aceitos.
  - A entrada pode ser enviada para recebimento mobile, ficando aberta para conferencia por camera/codigo de barras.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/stock_entries_screen.dart`
  - `admin_app/admin_flutter/lib/services/file_download.dart`
  - `admin_app/admin_flutter/lib/services/file_download_web.dart`
  - `admin_app/admin_flutter/lib/services/file_download_stub.dart`
- Banco de dados envolvido:
  - Sem nova tabela; usa `products`, `stock_entries`, `stock_entry_items`, `stock_movements` e `product_batches`.
- Como validar:
  - Abrir Entradas e conferir as abas operacionais.
  - Baixar o modelo de planilha.
  - Preencher uma linha com produto novo e importar o XLSX.
  - Confirmar que o produto e criado quando houver permissao e que os itens aparecem em conferencia.
  - Confirmar recebimento e verificar aumento de estoque/custo medio.

## Recebimento mobile com leitura de codigo de barras

- Modulo afetado: Entradas / Estoque / Aplicativo mobile.
- Objetivo: permitir conferencia fisica de mercadoria pelo celular, com fluxo rapido de camera.
- Comportamento esperado:
  - No computador, a entrada pode ser enviada para celular como recebimento aberto.
  - O menu possui a tela Receber, focada em celulares.
  - A tela Receber lista recebimentos abertos e abre a camera para leitura de codigo de barras.
  - Ao ler o codigo, o app localiza produto existente ou abre cadastro rapido com o codigo preenchido.
  - O usuario informa quantidade, unidade, custo, preco de venda, lote, validade, NCM/CFOP e observacao quando necessario.
  - Ao salvar o item, o app volta para a camera para o proximo produto.
  - A conferencia salva quantidades recebidas, mas o estoque so e movimentado ao finalizar o recebimento.
- Backend envolvido:
  - `backend/app/api/routes/stock_entries.py`
  - `backend/app/schemas/stock_entry.py`
  - `backend/app/models/stock_entry.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/mobile_receiving_screen.dart`
  - `admin_app/admin_flutter/lib/screens/stock_entries_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/models/stock_entry.dart`
- Banco de dados envolvido:
  - `stock_entries.status = receiving`.
  - `stock_entry_items.received_quantity`.
- Como validar:
  - Criar/importar uma entrada no computador.
  - Clicar em Enviar para celular.
  - Abrir Receber, selecionar a entrada e ler/informar um codigo.
  - Salvar o item e confirmar que a tela volta para camera.
  - Finalizar recebimento e confirmar que estoque e custo medio foram atualizados.

## Financeiro com contas a receber por cliente

- Modulo afetado: Financeiro / Vendas / PDV / Caixa.
- Objetivo: separar crediario do fechamento de caixa e controlar a divida consolidada de cada cliente.
- Comportamento esperado:
  - Vendas e PDV continuam gerando conta a receber quando a forma de pagamento for crediario.
  - A tela Caixa mostra somente fechamentos de turno, divergencias, sangrias e suprimentos.
  - A tela Financeiro lista Contas a Receber agrupadas por cliente.
  - O extrato do cliente mostra cada titulo, venda vinculada, itens comprados, valores, pagamentos e saldo.
  - A baixa permite recebimento parcial ou total com forma de recebimento e observacao.
  - O usuario pode baixar uma compra especifica ou receber um valor geral do cliente.
  - Recebimento geral do cliente e aplicado automaticamente nos titulos vencidos/mais antigos primeiro.
  - Contas a Pagar fica como area separada para futura ligacao com fornecedores e entradas.
- Backend envolvido:
  - `backend/app/models/receivable.py`
  - `backend/app/schemas/receivable.py`
  - `backend/app/api/routes/receivables.py`
  - `backend/app/core/permissions.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/finance_screen.dart`
  - `admin_app/admin_flutter/lib/screens/cash_closings_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/models/receivable.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
- Banco de dados envolvido:
  - `receivables`.
  - `receivable_payments`.
  - Relacionamento com `sales`, `sale_items` e `clients`.
- Como validar:
  - Fazer venda crediario para um cliente cadastrado.
  - Abrir Financeiro e confirmar que o cliente aparece com saldo.
  - Abrir o extrato e conferir venda, itens e saldo.
  - Registrar baixa parcial e confirmar que o saldo diminui.
  - Registrar recebimento geral do cliente menor que a divida total e confirmar que os titulos antigos sao quitados primeiro e o saldo parcial fica no proximo titulo.
  - Abrir Caixa e confirmar que o crediario nao aparece mais como painel de cobranca.

## Area de Configuracoes com modulo Fiscal

- Modulo afetado: App Admin Flutter / Fiscal.
- Objetivo: manter o menu lateral focado nos fluxos operacionais do dia a dia do ERP.
- Comportamento esperado:
  - O item direto `Fiscal` sai do menu lateral.
  - O menu lateral passa a mostrar `Configuracoes` para todos os usuarios de empresas/tenants.
  - Dentro de Configuracoes, a opcao Fiscal so aparece quando o master liberar o modulo/permissoes fiscais para a empresa e o usuario tiver acesso fiscal.
  - A opcao Fiscal abre a tela existente de certificado A1, CSC/ID, NFC-e, NF-e e documentos fiscais.
  - As permissoes continuam usando `fiscal:view`, `fiscal:settings` e `fiscal:documents:view`.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/screens/settings_screen.dart`
  - `admin_app/admin_flutter/lib/screens/fiscal_screen.dart`
- Banco de dados envolvido:
  - Sem alteracao de schema.
- Como validar:
  - Logar com usuario que tenha permissao fiscal.
  - Confirmar que `Fiscal` nao aparece no menu lateral.
  - Abrir `Configuracoes` e acessar a opcao Fiscal.
  - Confirmar que certificado A1, CSC/ID e documentos fiscais continuam carregando.

## Modulo de Relatorios gerenciais

- Modulo afetado: Relatorios / Estoque / Vendas / Financeiro / Entradas / Caixa / Clientes.
- Objetivo: centralizar analises gerenciais e permitir exportacao dos dados operacionais do ERP.
- Comportamento esperado:
  - O menu lateral exibe `Relatorios` para usuarios com acesso a algum modulo reportavel.
  - A tela inicial funciona como biblioteca de relatorios, com cards por categoria: Estoque, Vendas, Financeiro, Compras, Caixa e Clientes.
  - Cada card abre o detalhe do relatorio.
  - Dentro do detalhe, o relatorio possui filtro contextual, tabela e exportacao CSV compativel com Excel.
  - Estoque possui posicao de estoque, estoque baixo, proximos ao vencimento e vencidos.
  - Vendas possui vendas por periodo, produtos mais vendidos e formas de pagamento.
  - Financeiro possui contas a receber, aging de clientes e contas a pagar.
  - Compras possui entradas recentes, compras por fornecedor e pendencias de conferencia.
  - Caixa possui fechamentos de caixa.
  - Clientes possui clientes com saldo em crediario e cadastro exportavel.
  - Aging de clientes e calculado automaticamente por vencimento dos titulos abertos, sem cadastro manual de faixas.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/reports_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/services/file_download.dart`
- Banco de dados envolvido:
  - Sem nova tabela; usa APIs existentes de produtos, vendas, contas a receber, contas a pagar, entradas, caixa e clientes.
- Como validar:
  - Abrir Relatorios no menu lateral.
  - Alternar categorias e relatorios.
  - Buscar por cliente/produto/fornecedor.
  - Exportar um relatorio e abrir o CSV no Excel.

## Vendedor responsavel em Vendas e PDV

- Modulo afetado: Vendas / PDV / Usuarios / Relatorios.
- Objetivo: separar operador de caixa de vendedor responsavel pela venda.
- Comportamento esperado:
  - Usuarios do ERP possuem `seller_code`, exibido como Codigo vendedor no cadastro de usuarios.
  - O PDV continua abrindo caixa com operador/PIN.
  - A venda do PDV nao exibe seletor manual de vendedor; o responsavel operacional vem do caixa aberto.
  - A tela Vendas tambem permite selecionar vendedor.
  - O backend grava `seller_user_id` na venda.
  - Se nenhum vendedor for informado, o backend usa o usuario logado como fallback.
  - Vendas finalizadas pela tela Vendas, com pagamento recebido, entram em um lote diario automatico no fluxo de Caixa para conferencia da tesouraria.
  - O lote diario consolida os valores por forma de pagamento e mantem um movimento individual por venda para auditoria.
  - Cancelamento antes da conferencia subtrai a venda do lote pendente; se o lote ja foi conferido, o sistema marca divergencia para ajuste da tesouraria.
  - Valores em crediario nao entram nesse controle automatico de Caixa; continuam no Contas a Receber.
  - A API de vendas possui rota para listar vendedores ativos sem exigir permissao de gerenciamento de usuarios.
- Backend envolvido:
  - `backend/app/models/user.py`
  - `backend/app/models/sale.py`
  - `backend/app/schemas/user.py`
  - `backend/app/schemas/sale.py`
  - `backend/app/api/routes/admin.py`
  - `backend/app/api/routes/sales.py`
  - `backend/app/migrate_local.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/system_user.dart`
  - `admin_app/admin_flutter/lib/models/sale.dart`
  - `admin_app/admin_flutter/lib/models/session.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/screens/users_screen.dart`
  - `admin_app/admin_flutter/lib/screens/sales_screen.dart`
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
- Banco de dados envolvido:
  - `users.seller_code`.
  - `sales.seller_user_id`.
- Como validar:
  - Abrir Usuarios e conferir Codigo vendedor.
  - Abrir PDV, selecionar vendedor e finalizar venda.
  - Conferir no banco/API que a venda ficou com `seller_user_id`.
  - Abrir Vendas e repetir o fluxo.
  - Abrir Caixa e confirmar que vendas administrativas pagas do mesmo dia aparecem agrupadas em um lote diario pendente.

## Contas a pagar com fornecedores, entradas e despesas avulsas

- Modulo afetado: Financeiro / Fornecedores / Entradas.
- Objetivo: iniciar Contas a Pagar com estrutura de ERP, vinculado ao que o sistema ja possui.
- Comportamento esperado:
  - A aba A pagar lista titulos com fornecedor, vencimento, valor original, pago, saldo e status.
  - E possivel criar conta vinculada a fornecedor ou como despesa avulsa sem fornecedor.
  - A estrutura de backend permite vinculo opcional com entrada de mercadoria.
  - Baixas podem ser parciais ou totais, registrando forma de pagamento, usuario, data e observacao.
- Backend envolvido:
  - `backend/app/models/payable.py`
  - `backend/app/schemas/payable.py`
  - `backend/app/api/routes/payables.py`
  - `backend/app/api/router.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/payable.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/screens/finance_screen.dart`
- Banco de dados envolvido:
  - `payables`.
  - `payable_payments`.
- Como validar:
  - Abrir Financeiro > A pagar.
  - Criar nova conta a pagar com ou sem fornecedor.
  - Registrar baixa parcial e confirmar que o saldo fica parcial.
  - Registrar baixa restante e confirmar status pago.

## Permissoes separadas para PDV e Vendas

- Modulo afetado: Permissoes / PDV / Vendas / Master Empresas.
- Objetivo: permitir que uma pessoa tenha somente o botao PDV sem liberar o botao Vendas/historico.
- Comportamento esperado:
  - O botao PDV aparece quando o usuario possui `sales:create` / Operar PDV.
  - O botao Vendas aparece quando o usuario possui `sales:view` / Ver vendas.
  - O modelo de perfil "Somente PDV" libera PDV sem incluir `sales:view`.
  - O papel padrao Operador de caixa tambem fica focado em PDV, sem herdar Vendas.
  - No master, os modulos exibem "Vendas de PDV" separado de "Historico de vendas".
- Backend envolvido:
  - `backend/app/core/permissions.py`
  - `backend/app/services/access_control.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/settings_screen.dart`
  - `admin_app/admin_flutter/lib/screens/companies_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
- Banco de dados envolvido:
  - Sem mudanca de schema.
  - Exige rodar seed/migracao local para atualizar permissoes e remover `sales:view` do papel padrao Operador de caixa quando aplicavel.
- Como validar:
  - Criar perfil usando o modelo "Somente PDV".
  - Entrar com usuario desse perfil e confirmar que aparece PDV, mas nao Vendas.
  - Criar perfil com "Ver vendas" e sem "Operar PDV" e confirmar que aparece Vendas, mas nao PDV.

## Estabilidade na abertura de caixa do PDV Web

- Modulo afetado: PDV / Sessao do site.
- Objetivo: evitar tela vermelha ou tela branca ao autorizar fiscal/operador para abrir o caixa no Flutter Web.
- Comportamento esperado:
  - O fiscal autoriza a abertura sem quebrar a tela.
  - O operador abre o caixa normalmente depois da autorizacao.
  - Enquanto houver caixa aberto, a sessao do site nao expira por inatividade.
  - A atividade do usuario continua sendo registrada por clique, toque, mouse, roda do mouse e teclado.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/app.dart`
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
- Banco de dados envolvido:
  - Sem alteracao de schema.
  - Sem migracao adicional para essa correcao.
- Como validar:
  - Entrar no PDV.
  - Autorizar abertura com fiscal.
  - Informar operador/senha e abrir o caixa.
  - Confirmar que a tela nao fica vermelha/branca e que o PDV permanece operavel.

## Template

Usar [[00 - Entrada/Templates/Template - Funcionalidade|Template - Funcionalidade]] para novos registros.

## Contratos variaveis por apontamento

- Modulo afetado: Contratos / Estoque / Financeiro / Master Empresas / Permissoes.
- Objetivo: atender clientes que cobram servico recorrente com valor variavel por dias realmente atendidos na quinzena.
- Comportamento esperado:
  - O master libera o modulo `service_contracts` somente para empresas no plano Pro ou superior.
  - O cliente cria contrato por empresa/cliente, com valor por pessoa, quantidade padrao, data inicial e regras por tipo de dia.
  - As regras definem se atende/cobra em dia util, sabado, domingo e feriado, com multiplicador proprio.
  - O contrato pode ter produtos consumidos por pessoa para gerar baixa de estoque no apontamento.
  - O periodo gera apontamentos diarios editaveis; dias sem atendimento ficam sem cobranca.
  - Confirmar apontamento baixa estoque dos produtos levados/consumidos.
  - Cancelar apontamento estorna a baixa de estoque quando ela ja tiver sido feita.
  - Editar produtos/quantidades de um apontamento que ja baixou estoque estorna automaticamente a baixa anterior; depois o usuario confirma novamente para baixar o estoque corrigido.
  - O fechamento quinzenal soma os apontamentos cobrados e gera contas a receber.
- Backend envolvido:
  - `backend/app/models/service_contract.py`
  - `backend/app/schemas/service_contract.py`
  - `backend/app/api/routes/service_contracts.py`
  - `backend/app/services/company_modules.py`
  - `backend/app/core/permissions.py`
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/models/service_contract.dart`
  - `admin_app/admin_flutter/lib/services/api_client.dart`
  - `admin_app/admin_flutter/lib/screens/service_contracts_screen.dart`
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`
  - `admin_app/admin_flutter/lib/screens/companies_screen.dart`
  - `admin_app/admin_flutter/lib/screens/settings_screen.dart`
- Banco de dados envolvido:
  - Novas tabelas: `service_contracts`, `service_contract_attendance_rules`, `holidays`, `service_contract_consumption_items`, `service_appointments`, `service_appointment_consumption_items`, `service_billings`, `service_billing_items`.
  - Exige migracao/`Base.metadata.create_all` no servidor antes de usar.
- Observacao de servidor:
  - Ainda nao gerar pacote no HD externo ate o usuario pedir.
  - Quando gerar atualizacao, incluir roteiro de migracao para preservar dados reais do servidor.

## PDV Windows separado do PDV Web

- Modulo afetado: App Windows / PDV.
- Objetivo: continuar o PDV dedicado para Windows sem transformar visualmente o PDV do site.
- Comportamento esperado:
  - O app Windows usa o entrypoint `admin_app/admin_flutter/lib/main_pdv.dart`.
  - O PDV do site continua usando `main.dart` e `AppShell`.
  - O app Windows nao mostra tela de login operacional; ele usa configuracao local de terminal.
  - Ao abrir, o terminal deve mostrar somente `CAIXA FECHADO` quando estiver conectado, sem texto explicativo grande na tela.
  - Pressionar Enter com caixa fechado continua sendo atalho silencioso para solicitar codigo/senha do fiscal; depois pede operador e fundo inicial.
  - A configuracao local fixa `Servidor API`, `Empresa`, usuario tecnico e senha do terminal para evitar mistura de bancos entre empresas.
  - A configuracao do PDV Windows nao aceita a empresa `master`; deve apontar para uma empresa cliente/tenant.
  - O app Windows exige que o usuario tecnico configurado tenha `sales:create`.
  - O modo Windows ativa uma aparencia propria no caixa sem alterar o comportamento padrao do site.
  - Com caixa aberto, o app Windows usa layout escuro de terminal: venda/itens no lado esquerdo e operacao/resumo no lado direito.
  - Formas de pagamento aparecem somente na tela de pagamento, nao na tela principal do PDV Windows.
  - Atalhos do PDV Windows: F1 pesquisar produto, F2 codigo/bipagem, F3/F4 desconto, F6/F12 pagamento, F7 sangria, F8 fechar caixa, F10 cancelar item e F11 cancelar venda.
  - Acoes sem item no PDV Windows, como desconto/pagamento/cancelar item, nao exibem alerta grande; apenas mantem foco operacional.
  - A janela do app Windows nao pode ser fechada pelo X enquanto houver caixa aberto; e obrigatorio fazer o fechamento de caixa primeiro.
  - Layout fica preparado para evoluir acoes fiscais/NFC-e quando o cliente configurar certificado A1 no modulo Fiscal.
  - O executavel nativo passa a se chamar `lyncar_pdv.exe` e a janela aparece como `Lyncar PDV`.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/main_pdv.dart`
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
  - `admin_app/admin_flutter/windows/CMakeLists.txt`
  - `admin_app/admin_flutter/windows/runner/main.cpp`
  - `admin_app/admin_flutter/windows/runner/Runner.rc`
- Banco de dados envolvido:
  - Sem alteracao de schema.
- Como validar:
  - Rodar `flutter build windows -t lib/main_pdv.dart`.
  - Abrir `build/windows/x64/runner/Release/lyncar_pdv.exe`.
  - Confirmar janela `Lyncar PDV`.
  - Entrar com empresa/usuario autorizado ao PDV e abrir caixa.

## Atualizacao servidor - Contratos variaveis

- Data: 14/06/2026.
- Pacote gerado no HD externo:
  - `E:\ATUALIZACAO_PAPEZZOSYNC_CONTRATOS_VARIAVEIS_2026-06-14_22-45-27`
  - `E:\ATUALIZACAO_PAPEZZOSYNC_CONTRATOS_VARIAVEIS_2026-06-14_22-45-27.zip`
- Escopo: somente o que faltava apos o pacote ja enviado ao servidor: modulo Contratos variaveis / Recorrencia por apontamento, permissao, menu, API, build web e roteiro de migracao.
- Observacao: nao leva dados locais, `.env`, uploads, IP, dominio, Cloudflare, APK ou PDV Windows.
- Banco: exige rodar `python -m app.migrate_local` no servidor para criar as tabelas que faltarem, preservando os dados reais do servidor.

## Contratos variaveis - busca e historico de clientes

- Data: 16/06/2026.
- Modulo afetado: Contratos variaveis.
- Objetivo: facilitar localizar contratos por cliente e permitir encerrar um cliente/contrato sem apagar historico.
- Comportamento esperado:
  - A lista lateral de contratos possui campo de pesquisa por cliente, descricao, numero do contrato e valor.
  - A lista lateral separa contratos ativos e historico.
  - Encerrar cliente/contrato marca o contrato como inativo/encerrado e move para Historico.
  - Reativar contrato move o contrato de volta para Ativos.
  - Fechamentos, apontamentos e Contas a Receber vinculados permanecem preservados.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/service_contracts_screen.dart`.
- Banco de dados envolvido:
  - Sem alteracao de schema; usa os campos existentes `active` e `status` de `service_contracts`.
- Como validar:
  - Abrir Contratos variaveis.
  - Pesquisar pelo nome do cliente.
  - Encerrar um contrato ativo e confirmar que ele sai de Ativos e aparece em Historico.
  - Reativar o contrato e confirmar que volta para Ativos.
  - Abrir a aba Historico de fechamentos do contrato e confirmar que os fechamentos continuam visiveis.

## Contratos variaveis - feriados automaticos

- Data: 16/06/2026.
- Modulo afetado: Contratos variaveis.
- Objetivo: evitar que o usuario precise clicar em atualizar feriados ou cadastrar todos manualmente antes de gerar apontamentos.
- Comportamento esperado:
  - Ao gerar apontamentos ou fechar quinzena, o backend garante automaticamente os feriados do ano do periodo.
  - Feriados nacionais sao buscados automaticamente pela BrasilAPI e salvos na tabela `holidays`.
  - Feriados municipais/estaduais sao buscados automaticamente quando houver `FERIADOS_API_TOKEN` configurado e o cliente possuir cidade e UF.
  - Para localizar a cidade, o backend consulta a API de localidades do IBGE e resolve o codigo IBGE a partir de cidade/UF.
  - Se a internet ou a API externa falhar, o fechamento nao trava; o sistema usa os feriados ja existentes no banco.
  - Cadastro manual de feriados continua funcionando como complemento.
- Backend envolvido:
  - `backend/app/services/holidays.py`.
  - `backend/app/api/routes/service_contracts.py`.
  - `backend/app/core/config.py`.
- Banco de dados envolvido:
  - Sem alteracao de schema; usa a tabela existente `holidays`.
- Configuracao:
  - `HOLIDAY_SYNC_ENABLED=true` por padrao.
  - `FERIADOS_API_TOKEN` libera feriados municipais/estaduais via API externa.
- Como validar:
  - Remover feriados nacionais de um ano de teste e gerar periodo desse ano.
  - Confirmar que os feriados nacionais foram criados em `holidays`.
  - Configurar `FERIADOS_API_TOKEN`, usar cliente com cidade/UF e gerar periodo.
  - Confirmar que feriados municipais/estaduais da cidade aparecem em `holidays` e que dias correspondentes viram tipo `holiday`.

## Contratos variaveis - recálculo de apontamentos abertos após feriado

- Data: 16/06/2026.
- Modulo afetado: Contratos variaveis.
- Objetivo: corrigir periodos que ja tinham sido gerados antes da sincronizacao/cadastro de feriados.
- Comportamento esperado:
  - Ao buscar, gerar ou fechar um periodo, apontamentos existentes ainda abertos podem ser recalculados pela regra atual de calendario.
  - Se um dia que era util passa a ser feriado, o apontamento aberto muda para `holiday`.
  - Se a regra de feriado nao atende/nao cobra, o apontamento fica `sem_atendimento`, com pessoas `0` e valor `0`.
  - Apontamentos confirmados, com estoque baixado ou ja incluidos em fechamento ativo nao sao alterados automaticamente.
- Observacao local:
  - No tenant `papezzosync_drika_padaria`, foi cadastrado o feriado municipal de Leme/SP em 17/06/2026, Dia de Sao Manoel, e o apontamento aberto do contrato `CT1` foi corrigido para feriado sem atendimento.

## Fiscal opcional no PDV e Central de recebimentos

- Data: 18/06/2026.
- Modulos afetados: Fiscal, PDV e Entradas de mercadoria.
- Objetivo: permitir que a empresa use o PDV sem emissao automatica enquanto completa o cadastro fiscal e organizar o recebimento de notas como fluxo principal de ERP.
- Comportamento esperado:
  - Configuracoes fiscais possuem controle separado `Emitir NFC-e automaticamente no PDV`.
  - Desligar esse controle nao desliga vendas, pagamentos nem baixa de estoque do PDV.
  - O PDV nao solicita CPF/CNPJ e nao prepara/envia NFC-e quando o controle estiver desligado.
  - Entradas abre primeiro a Central de recebimentos, com pesquisa e filtros.
  - Nota aberta pode ser recebida no computador ou enviada ao coletor.
  - O formulario do computador atualiza a entrada existente, evitando duplicidade.
  - Somente a finalizacao movimenta estoque e custo medio.
- Backend envolvido:
  - `backend/app/models/fiscal.py`.
  - `backend/app/schemas/fiscal.py`.
  - `backend/app/api/routes/fiscal.py`.
  - `backend/app/api/routes/stock_entries.py`.
  - `backend/app/migrate_local.py`.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/fiscal_screen.dart`.
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`.
  - `admin_app/admin_flutter/lib/screens/stock_entries_screen.dart`.
  - `admin_app/admin_flutter/lib/models/fiscal.dart`.
  - `admin_app/admin_flutter/lib/services/api_client.dart`.
- Banco de dados envolvido:
  - Novo campo `company_fiscal_settings.pdv_nfce_enabled`, booleano, com padrao `false`.
- Como validar:
  - Desligar Fiscal no PDV e concluir uma venda sem emissao e sem pedido de documento.
  - Abrir Entradas, pesquisar nota/chave/fornecedor e alternar filtros.
  - Abrir nota em recebimento no computador, salvar na mesma entrada e confirmar que nao foi criada duplicata.
  - Enviar entrada ao coletor e confirmar que permanece aberta.
  - Finalizar no computador e confirmar movimentacao de estoque.

## Caixa de XML individual por tenant

- Data: 18/06/2026.
- Modulos afetados: Entradas, Fiscal, tenancy e cadastro master de empresas.
- Objetivo: permitir que fornecedores enviem XML de NF-e para um endereco exclusivo e a nota apareca automaticamente na Central de recebimentos.
- Comportamento implementado:
  - Cada empresa recebe alias `xml+empresa-token@notas.lyncar.com.br`.
  - Token e estado do endereco ficam no master; mensagens e XMLs ficam no tenant.
  - Endpoint de entrada exige segredo do provedor.
  - XML e analisado antes da importacao.
  - CNPJ de `dest` diferente do CNPJ fiscal gera `cnpj_mismatch`.
  - Rejeicao por CNPJ nao armazena o XML e nao cria entrada.
  - Chave ja importada gera `duplicate`.
  - XML aceito gera entrada `receiving` com origem `email_xml`.
  - Tela Entradas exibe endereco, botao de copiar e historico sanitizado da Caixa.
- Teste local:
  - Endereco da Drika: `xml+drika_padaria-uunbztpr@notas.lyncar.com.br`.
  - XML fake NF 9001 com destinatario `63816719000115`: importado na entrada #4.
  - XML fake NF 9002 com destinatario `11222333000144`: rejeitado sem entrada e sem conteudo armazenado.
  - Reenvio da chave da NF 9001: rejeitado como duplicado.
- Dependencia para producao:
  - Configurar DNS/MX e provedor de recebimento para `notas.lyncar.com.br`.
  - Configurar `XML_INBOUND_SECRET` forte no `.env`.
  - Adaptar o webhook do provedor escolhido ao endpoint `/xml-inbox/inbound/{routing_token}`.

## Cupom nao fiscal automatico no PDV

- Data: 18/06/2026.
- Modulos afetados: PDV e impressao web.
- Objetivo: entregar comprovante da venda mesmo quando a emissao fiscal estiver desativada.
- Comportamento:
  - PDV fiscal pronto/ativo segue com NFC-e.
  - Sem emissao fiscal, a venda abre automaticamente a impressao de cupom nao fiscal.
  - Cupom em largura termica de 80 mm.
  - Exibe itens, valores, pagamentos, recebido, troco, operador e observacoes.
  - Exibe `CUPOM NAO FISCAL`, `NAO E DOCUMENTO FISCAL` e `Comprovante comercial sem valor fiscal`.
  - Impressao web usa iframe temporario para nao depender de popup liberado pelo navegador.
  - No app Windows, o cupom texto e enviado para a impressora padrao do sistema pelo spooler do Windows.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/pdv_screen.dart`.
  - `admin_app/admin_flutter/lib/services/receipt_print_web.dart`.
  - `admin_app/admin_flutter/lib/services/receipt_print_stub.dart`.
  - `admin_app/admin_flutter/lib/services/receipt_print_io.dart`.
- Banco de dados:
  - Sem alteracao de schema.
- Como validar:
  - Desligar `Emitir NFC-e automaticamente no PDV`.
  - Finalizar uma venda.
  - Confirmar abertura da janela de impressao com cupom nao fiscal.
  - Confirmar ausencia de chave, protocolo e QR Code SEFAZ.

## Tela operacional de Notas fiscais

- Data: 18/06/2026.
- Modulos afetados: Fiscal, navegacao e permissoes.
- Objetivo: separar configuracao fiscal da rotina diaria de emissao e consulta.
- Comportamento implementado:
  - `Configuracoes > Fiscal` fica restrito a A1, CSC/ID, series e cadastro tributario.
  - Novo destino `Notas fiscais` no menu lateral para usuarios com `fiscal:documents:view`.
  - Resumo de total, autorizadas, pendentes e rejeitadas.
  - Pesquisa por nota, venda, CPF/CNPJ, destinatario e chave.
  - Filtros por tipo e status.
  - Preparacao de NFC-e a partir de venda finalizada sem documento.
  - Envio de NFC-e modelo 65 para o motor SEFAZ existente.
  - Detalhes com chave, protocolo, retorno SEFAZ e datas.
  - NF-e 55, impressao DANFE e cancelamento permanecem bloqueados com aviso de motor pendente.
  - Cancelamento nao altera apenas o status local.
- Frontend envolvido:
  - `admin_app/admin_flutter/lib/screens/fiscal_documents_screen.dart`.
  - `admin_app/admin_flutter/lib/screens/fiscal_screen.dart`.
  - `admin_app/admin_flutter/lib/screens/app_shell.dart`.
  - `admin_app/admin_flutter/lib/models/fiscal.dart`.
- Banco de dados:
  - Sem alteracao de schema.
- Validacao:
  - `flutter analyze`: sem problemas.
  - `flutter build web --release`: concluido.
  - Interface validada no navegador com 29 documentos de homologacao.

# Regras de Negocio

## Privacidade e monitoramento

- O monitoramento deve coletar apenas dados de desempenho e saude da maquina.
- O agente nao deve capturar tela.
- O agente nao deve acessar arquivos pessoais.
- O agente nao deve coletar senhas.
- O agente nao deve coletar dados privados do usuario.
- Cada maquina monitorada deve estar vinculada a um cliente.

## Acesso e permissoes

- Admin ve e gerencia tudo.
- Tecnico acessa chamados, equipamentos, ordens de servico, manutencoes e monitoramento.
- Vendedor acessa clientes, produtos, estoque, orcamentos e vendas futuras.
- Cliente acessa apenas seus proprios dados, chamados, maquinas e ordens de servico.
- O portal do cliente nunca deve mostrar dados de outros clientes.

## Multiempresa e SaaS

- O PapezzoSync deve permitir que cada empresa cliente tenha dados separados.
- A PapezzoSync como dona do sistema deve ter uma camada master para cadastrar e administrar empresas clientes do sistema.
- O superadmin master e superior a qualquer empresa/tenant e nao deve ser tratado como cliente do sistema.
- O login master usa empresa `master` e acessa apenas o painel de controle global.
- O painel master nao deve aparecer como modulo comum dentro do ERP vendido aos clientes.
- Cada empresa cliente deve acessar o sistema usando um codigo de empresa no login enquanto nao houver dominio/subdominio proprio.
- A estrategia futura recomendada e usar subdominio por empresa, mantendo a mesma interface visual.
- Dados de estoque, vendas, OS, clientes, operadores, usuarios e monitoramento nao devem misturar empresas diferentes.
- A assistencia tecnica Papezzo deve ser tratada como uma empresa/tenant dentro do sistema, separada da camada master.
- O cadastro master de empresa deve guardar dados comerciais/fiscais, contato, endereco, plano, forma de pagamento e mensalidade.
- O cadastro master deve definir segmento e modulos contratados por empresa.
- Empresas de comercio como padaria, mercado e loja nao devem receber modulos tecnicos como OS, maquinas e monitoramento, salvo liberacao manual.
- Empresas de assistencia tecnica devem receber OS, maquinas, chamados e monitoramento.
- A dashboard tecnica com maquinas, online/offline, chamados e alertas deve aparecer somente para empresas de assistencia tecnica ou empresas com modulos de maquinas/monitoramento contratados.
- Empresas sem modulo tecnico devem ver uma dashboard-vitrine SaaS separada em tres areas: Avisos, Certificado Digital A1 e Loja Lyncar.
- Avisos aparecem no topo. Se nao houver aviso ativo, o card de certificado pode ocupar esse espaco como destaque.
- A vitrine de Certificado Digital A1 nao deve aparecer para empresas que ja possuem certificado fiscal A1 cadastrado no proprio tenant.
- A Loja Lyncar deve aceitar produtos proprios, links afiliados e links de compra externa/WhatsApp enquanto nao houver pagamento integrado.
- Avisos, Certificados e Loja Lyncar podem ter imagem cadastrada pelo master. A imagem deve ser tratada como midia publica de vitrine, nao como dado sensivel.
- Conteudos da dashboard-vitrine ficam no banco master e podem ser exibidos para todos, por segmento da empresa ou por modulo contratado, sem misturar dados operacionais dos tenants.
- Telas operacionais com listas devem ter busca simples e filtros avancados quando o volume de dados puder crescer, como estoque, clientes, vendas, caixa, entradas e conteudos master.
- A busca deve aceitar texto parcial e ignorar diferencas basicas de maiusculas/minusculas e acentos.
- Filtros avancados devem respeitar o contexto do modulo, como status, tipo, periodo, origem, estoque baixo, lote/validade e faixa de valor.
- O ERP deve ter modulo central de Relatorios, alem de exportacao nas telas operacionais quando fizer sentido.
- Relatorios centrais devem ser organizados por area: Estoque, Vendas, Financeiro, Compras/Entradas, Caixa e Clientes.
- A tela inicial de Relatorios deve funcionar como biblioteca de relatorios, com um botao/card para cada relatorio.
- Ao abrir um relatorio especifico, os filtros e a exportacao devem aparecer dentro do detalhe daquele relatorio, conforme o contexto dele.
- Relatorios devem permitir busca, visualizacao tabular e exportacao para arquivo editavel, inicialmente CSV compativel com Excel.
- Aging de clientes deve ser calculado automaticamente a partir da data de vencimento dos titulos em aberto do Contas a Receber, separando saldos a vencer, 0-30, 31-60, 61-90 e acima de 90 dias de atraso.

## PDV e caixa

- Operador de PDV deve ser separado de usuario completo do ERP.
- Operador de caixa usa codigo e senha/PIN para abrir e operar o caixa.
- Operador de caixa registra quem operou o caixa, mas nao substitui o vendedor responsavel pela venda.
- Todo usuario do ERP pode possuir codigo de vendedor para ser selecionado em Vendas/PDV e aparecer em relatorios/comissoes futuras.
- Venda deve guardar `seller_user_id` do vendedor responsavel. Quando nao informado, usa o usuario logado como fallback.
- A tela PDV nao deve exibir seletor manual de vendedor; o responsavel operacional do caixa vem do operador/login que abriu o caixa.
- A tela Vendas deve manter seletor de vendedor, pois representa venda administrativa/comercial fora do caixa.
- Venda finalizada pela tela Vendas, fora do PDV, deve entrar automaticamente no fluxo de Caixa quando houver pagamento recebido.
- O PDV fecha por caixa/turno/operador, pois representa controle fisico de gaveta, dinheiro, sangrias e suprimentos.
- Vendas administrativas feitas pela tela Vendas nao devem gerar uma conferencia separada por venda; devem ser agrupadas em um lote diario pendente para conferencia da tesouraria.
- O lote diario automatico da tela Vendas deve somar vendas pagas do mesmo dia, manter movimentos individuais por venda para auditoria e excluir valores em crediario que pertencem ao Contas a Receber.
- Fiscal/supervisor de caixa usa codigo e senha/PIN para autorizar acoes sensiveis.
- Sangria, cancelamento e descontos devem exigir autorizacao de fiscal quando configurado.
- Caixa aberto nao deve ser encerrado automaticamente por inatividade da sessao administrativa.
- Ao fechar o caixa, o comportamento normal de expiracao por inatividade volta a valer.
- O PDV deve ter modo focado/tela cheia para operacao de caixa, reduzindo distracoes do ERP administrativo.

## Estoque, custo e producao

- O estoque deve controlar custo medio ponderado por movimentacao de entrada.
- O valor de compra informado no cadastro pode representar um lote ou pacote; por isso deve existir quantidade base do custo.
- Exemplo: 5 kg por R$ 25,00 significa custo base de R$ 5,00/kg, nao R$ 25,00/kg.
- Ficha tecnica, ordem de producao, vendas e PDV devem usar o custo medio/base correto do produto, respeitando conversao de unidades compativeis.
- Saidas de estoque devem registrar custo de estoque, nao preco de venda. O preco de venda fica no documento da venda.
- Vendas e PDV podem deixar estoque negativo quando o saldo cadastrado estiver incorreto, para nao travar a operacao do caixa.
- Estoque negativo deve continuar gerando movimento de saida no historico, permitindo auditoria, ajuste posterior e correcao de saldo.
- O produto acabado produzido deve receber entrada no estoque pelo custo total real dos componentes consumidos.
- A ordem de producao deve ter ciclo operacional: planejada, em producao, concluida e cancelada.
- Criar uma ordem de producao nao deve alterar estoque; estoque muda somente ao concluir ou ao estornar uma OP concluida.
- A conclusao da OP deve validar estoque suficiente dos componentes no momento da conclusao, usando a ficha tecnica vigente.
- Cancelamento de OP concluida so pode estornar quando o produto acabado ainda tiver saldo suficiente para sair do estoque.
- Toda OP deve manter custo estimado e custo real, componentes consumidos, usuario responsavel e historico de movimentos.
- Produtos com lote/validade devem manter saldo por lote.
- Entrada de mercadoria aceita cria ou soma saldo no lote informado.
- Venda, PDV e consumo de producao devem baixar lotes pelo criterio FIFO de validade, usando primeiro o lote que vence antes.
- A tela de estoque deve permitir consultar lotes, saldos e validade do produto.
- Produtos/mercadorias/materias-primas podem ter imagem cadastrada. A imagem aparece como identificacao visual no estoque e deve ficar vinculada ao produto no banco do tenant.
- Entrada de mercadoria deve ser a forma oficial de aumentar estoque comprado.
- Importacao de XML de NF-e enviado pelo fornecedor e gratuita e deve funcionar sem certificado.
- A tela de entrada deve separar claramente os fluxos de recebimento manual, importacao de NF-e por XML, importacao por planilha e consulta futura por chave NF-e.
- Importacao por planilha deve disponibilizar modelo padrao baixavel, editavel no Excel, para primeira carga ou compra grande.
- Entradas podem ser salvas como recebimento aberto para conferencia mobile, sem movimentar estoque imediatamente.
- No celular, o recebimento deve ser scan-first: abrir camera, ler codigo de barras, localizar/criar produto, pedir dados do item, salvar e voltar automaticamente para a camera.
- O recebimento mobile registra quantidades conferidas, lote, validade, custo e produto novo quando necessario, mas o estoque so deve ser movimentado ao finalizar/confirmar o recebimento.
- Produtos escaneados fora da nota podem ser adicionados ao recebimento com rastreabilidade, ficando visiveis na conferencia.
- A planilha de entrada deve permitir cadastrar produtos em massa quando ainda nao existirem, usando codigo interno/barras, nome, unidade, quantidade, custo, preco de venda, estoque minimo, categoria, marca, NCM, CFOP, lote e validade.
- Produtos vindos da planilha devem ser vinculados por codigo de barras ou codigo interno; quando nao houver vinculo nem permissao para criar produto, o item fica pendente de conferencia.
- Baixa de XML pela chave da NF-e exige certificado digital da propria empresa cliente.
- Cada tenant/empresa deve configurar e usar somente seu proprio certificado digital.
- Fornecedor deve ser cadastro proprio do tenant, separado de clientes e produtos.
- Entradas manuais podem informar fornecedor manualmente, mas XML de NF-e deve tentar vincular o fornecedor automaticamente pelo CNPJ/CPF do emitente.
- Se o XML trouxer fornecedor ainda nao cadastrado, a entrada deve orientar o cadastro/vinculo do fornecedor antes da confirmacao.
- A entrada de mercadoria deve manter snapshot do nome e documento do fornecedor para preservar o historico mesmo se o cadastro for alterado depois.
- Fornecedores devem ter permissao propria para visualizar, criar e editar, liberada por empresa/usuario.
- Fornecedores tambem devem ser um modulo liberavel no cadastro master da empresa. Empresas com modulo `stock` devem receber `suppliers` por padrao.
- O cadastro de clientes deve servir tanto para assistencia tecnica quanto para comercio.
- Em assistencia tecnica, cliente pode usar contrato avulso/mensal e se relacionar com OS, chamados, equipamentos e monitoramento.
- Em comercio, cliente representa consumidor/empresa para venda e crediario, com status de credito, limite, condicao de pagamento e observacoes financeiras.
- Crediario deve existir como forma de pagamento operacional em Vendas e PDV.
- Venda crediario deve exigir cliente selecionado e gerar uma conta a receber vinculada a venda.
- Crediario nao entra no dinheiro esperado do caixa e nao deve ser tratado como responsabilidade da tela Caixa.
- Caixa deve tratar somente fechamento de turno, formas de pagamento recebidas, sangrias, suprimentos, dinheiro esperado, dinheiro contado e divergencias.
- Crediario deve ser controlado no modulo Financeiro em Contas a Receber.
- Contas a Receber deve agrupar saldos por cliente, mantendo extrato de compras no crediario, itens vendidos, pagamentos parciais/totais e saldo atual.
- Baixa de crediario deve permitir pagamento parcial ou total, registrando forma de recebimento, valor, usuario e observacao.
- Recebimento por cliente deve permitir informar um valor para abater varias compras em aberto.
- Quando o cliente pagar um valor geral, o sistema deve aplicar automaticamente nos titulos vencidos/mais antigos primeiro, deixando baixa parcial no ultimo titulo quando o valor nao quitar tudo.
- Contas a Pagar deve ser modulo financeiro separado, ligado a fornecedores, entradas de mercadoria, vencimentos, pagamentos e conferencia de compras.
- Contas a Pagar deve trabalhar com titulos por fornecedor/despesa, valor original, valor pago, saldo, vencimento, competencia, status, baixas parciais/totais, anexos e relatorio de aging.
- Uma conta a pagar pode estar vinculada a fornecedor e entrada de mercadoria, mas tambem pode existir como despesa avulsa sem fornecedor.
- Administradores de uma empresa/tenant so podem conceder permissoes pertencentes aos modulos contratados/liberados pelo master para aquela empresa.
- Mesmo que um perfil padrao inclua mais acessos, a lista exibida e gravada no cadastro de usuarios deve ser filtrada pelos modulos contratados da empresa.
- Dentro de cada empresa/tenant, o cadastro de clientes nao deve permitir duplicidade por documento, e-mail, nome/telefone ou nome quando nao houver outros identificadores.
- E-mails de usuarios do ERP devem ser unicos globalmente no indice master `master_user_index`, mesmo com bancos separados por empresa. Nao deve existir opcao de criar o mesmo login em duas empresas diferentes, para evitar conflito de redirecionamento e autenticacao por dominio/subdominio.
- O cadastro master de empresas clientes do SaaS tambem nao deve permitir duplicidade por codigo/subdominio, documento, e-mail comercial ou nome da empresa.

## Manutencao desta nota

Registrar aqui regras permanentes do negocio. Detalhes operacionais ou temporarios devem ficar em tarefas, bugs ou funcionalidades.
## Fiscal, NFC-e/NF-e e certificado digital

- O Lynkar ERP/PDV deve priorizar NFC-e/NF-e com Certificado Digital A1 por empresa/tenant.
- SAT nao e o foco principal para novos clientes; deve ser tratado apenas como compatibilidade futura ou legado quando realmente necessario.
- Cada empresa emissora usa seu proprio certificado digital A1. O consumidor final nao precisa possuir certificado.
- O certificado e sua senha nunca devem ser tratados como dados comuns de cadastro. A regra final e armazenamento seguro/criptografado, com referencia tecnica no banco e segredo protegido fora do texto puro.
- Antes de finalizar uma venda fiscal no PDV, o sistema deve perguntar se o consumidor deseja informar CPF na nota.
- CPF do consumidor e opcional. Se o consumidor nao informar CPF, a venda e a NFC-e continuam normalmente quando a configuracao fiscal permitir.
- O documento fiscal deve ser separado da venda: a venda registra itens, pagamento e baixa de estoque; o documento fiscal registra XML, status SEFAZ, protocolo, chave de acesso, DANFE e envios.
- XML autorizado deve ser guardado por empresa/tenant e deve permitir consulta/download posterior.
- Produtos devem manter dados fiscais suficientes para emissao: NCM, CEST quando aplicavel, CFOP, origem, CST/CSOSN, aliquotas e campos preparados para IBS/CBS da Reforma Tributaria.
- Regras tributarias devem ser modulares e atualizaveis, para evitar reescrever o PDV quando houver mudanca legal.
- Cada tenant guarda seu proprio Certificado Digital A1 criptografado no proprio banco separado.
- O frontend nunca deve receber o arquivo do certificado, senha do certificado ou segredos internos. Deve receber somente status, nome, hash e metadados seguros.
- A baixa de XML pela chave da NF-e so pode avancar se a empresa tiver certificado fiscal cadastrado.
- Para NFC-e, a empresa pode precisar informar CSC/Token e ID do CSC no modulo Fiscal. O token deve ser tratado como segredo e nao deve ser exibido novamente depois de salvo.
# Caixa de XML por empresa

- Cada empresa possui endereco tecnico exclusivo para receber XML de NF-e.
- O endereco identifica o tenant, mas nunca substitui a validacao fiscal do documento.
- O CNPJ destinatario dentro do XML deve ser exatamente o CNPJ fiscal configurado no tenant.
- XML de outra empresa nao pode ser importado, nao pode criar entrada e nao deve ter seu conteudo armazenado.
- XML valido recebido por e-mail cria apenas uma entrada aberta; estoque e custo medio continuam dependendo da conferencia/finalizacao.
- A mesma chave NF-e nao pode gerar duas entradas.
- Conteudo de XML pertence ao tenant. O master ve apenas roteamento e disponibilidade do endereco, sem acesso ao documento.

# Cupom nao fiscal do PDV

- Desativar a emissao fiscal nao pode impedir a entrega de comprovante comercial da venda.
- O comprovante deve ser inequivocamente identificado como `CUPOM NAO FISCAL` e sem valor fiscal.
- Nenhuma chave, protocolo, QR Code ou indicacao de autorizacao SEFAZ pode aparecer no cupom nao fiscal.
- A venda, pagamentos, troco e movimentacao de estoque continuam registrados normalmente.

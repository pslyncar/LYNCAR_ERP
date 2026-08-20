# Produtos e Servicos

Este modulo passou a ser exibido na interface como **Estoque**, pois atende produtos, mercadorias de revenda, materias-primas, embalagens, pecas, insumos e servicos.

## Campos previstos

- Nome do produto ou servico.
- Tipo: produto, produto acabado, mercadoria/revenda, materia-prima, embalagem, peca, servico ou insumo.
- Codigo interno.
- Codigo de barras/EAN.
- Marca, modelo e categoria.
- Preco de venda.
- Valor de compra/base de custo, quando aplicavel.
- Quantidade base do custo, quando o valor de compra representar um lote/pacote.
- Custo medio atual do estoque.
- Valor total em estoque.
- Estoque, quando aplicavel.
- Unidade de medida.
- Localizacao no estoque.
- Controle de lote/validade quando aplicavel.
- Lote inicial e validade inicial para cadastros diretos sem XML.
- Proxima validade/lote na listagem de estoque, priorizando dados das entradas confirmadas.
- Botao de saldos por lote para visualizar lote, validade, saldo, origem, fornecedor e NF.
- Dados fiscais para venda e emissao futura de nota.
- Observacoes.
- Status: ativo ou inativo.

## Ficha tecnica / composicao

- Produtos finais podem ter uma ficha tecnica com componentes.
- Componentes podem ser materias-primas, insumos, embalagens ou outros itens cadastrados no estoque.
- Cada componente registra quantidade, unidade, percentual de perda e observacao.
- O custo da ficha tecnica usa o custo medio/base do componente na unidade de estoque, com conversao de unidade quando necessario.
- Exemplo: trigo cadastrado com 5 kg por R$ 25,00 gera custo base de R$ 5,00/kg; se a ficha usa 0,300 kg, o custo do componente e R$ 1,50.
- A ficha tecnica serve de base para a futura ordem de producao.
- Na futura ordem de producao, ao produzir um item:
  - entra estoque do produto acabado;
  - sai estoque das materias-primas/insumos conforme a composicao;
  - movimentos devem ser registrados no historico de estoque.

## Custo medio e valor de estoque

- O estoque deve trabalhar com custo medio ponderado por movimentacao de entrada.
- Entradas de estoque recalculam o custo medio do produto considerando quantidade atual, valor atual em estoque e custo da nova entrada.
- Saidas de estoque nao recalculam o custo medio; elas baixam o valor do estoque usando o custo medio vigente.
- Saidas de venda/PDV e consumo de producao tambem baixam saldo por lote quando o produto controla lote/validade.
- Vendas e PDV guardam o preco de venda na venda, mas o historico de estoque deve registrar o custo/valor de estoque para permitir CMV e relatorios financeiros.
- Os campos oficiais para base de compra sao `purchase_total_cost` e `purchase_quantity`; os campos oficiais calculados do estoque sao `average_cost` e `stock_value`.

## Cadastro, saldo e promocoes

- O cadastro do produto nao pode alterar `stock_quantity` depois da criacao. O saldo exibido nele e somente leitura.
- Recontagem e correcao usam ajuste rastreavel com saldo contado, motivo e observacao. O movimento guarda saldo anterior, diferenca, saldo final, usuario e data.
- Saldo negativo e valido e deve ser preservado; nunca pode ser convertido silenciosamente em positivo.
- Preco promocional, inicio e fim pertencem ao menu **Precos e promocoes**, separado do cadastro e do estoque.
- A tela de promocoes apresenta indicadores e filtros para ofertas ativas, agendadas, encerradas e produtos sem oferta, alem de busca e ordenacao.
- A criacao/edicao de oferta informa o desconto calculado, usa seletores de data e hora, oferece periodos rapidos e permite encerrar a oferta para restaurar imediatamente o preco normal.
- A listagem de promocoes e responsiva ao espaco disponivel com o menu lateral aberto ou fechado e nao exibe formularios repetidos em todos os produtos.
- O produto novo ainda pode receber estoque inicial; entradas de mercadoria continuam sendo a forma oficial de aumentar estoque comprado.

## Entrada de mercadoria e NF-e

- O modulo de estoque possui tela propria de Entradas.
- A tela principal de Entradas funciona como uma Central de recebimentos, com busca por numero da nota, chave, fornecedor e itens, alem de filtros por situacao e origem.
- Cada nota aberta oferece os caminhos `Receber no computador`, `Enviar ao coletor` e `Finalizar`.
- Receber no computador carrega a entrada existente no formulario de conferencia; salvar ou enviar ao coletor atualiza a mesma entrada, sem criar duplicata.
- Enviar ao coletor mantem a entrada no status de recebimento e disponivel no app mobile.
- Finalizar e a unica acao que movimenta estoque, lotes e custo medio. Entradas finalizadas ficam somente para consulta.
- Importacao por XML, consulta por chave, planilha e entrada manual ficam agrupadas na acao secundaria `Nova entrada`.
- Cada tenant recebe um endereco exclusivo da Caixa de XML no formato `xml+empresa-token@notas.lyncar.com.br`.
- O banco master guarda somente o token de roteamento e o estado ativo/inativo do endereco. O XML e os dados da nota ficam exclusivamente no banco tenant.
- Antes de importar, o backend compara o CNPJ do bloco `dest` da NF-e com o CNPJ de `company_fiscal_settings`.
- XML sem CNPJ destinatario correspondente e rejeitado, nao cria entrada e seu conteudo nao e armazenado.
- XML valido cria uma entrada aberta com origem `email_xml`, aguardando recebimento fisico no computador ou coletor.
- Reenvio da mesma chave NF-e e tratado como duplicado e nao cria nova entrada.
- A Caixa de XML mostra ao cliente eventos importados, CNPJ diferente, duplicidade, XML invalido e CNPJ fiscal nao configurado.
- O master nao possui endpoint para abrir ou baixar os XMLs dos tenants.
- A tela de Entradas deve separar os fluxos de recebimento manual, importacao de NF-e por XML, importacao por planilha e consulta futura por chave NF-e.
- Entrada manual deve permitir fornecedor, nota, produto, quantidade e custo unitario.
- Entrada manual passa por conferencia e gera movimento `purchase_in` apenas para itens aceitos.
- Importacao de NF-e por XML deve aceitar XML enviado pelo fornecedor, ler fornecedor, chave, numero, serie e itens.
- O XML deve tentar vincular automaticamente os itens aos produtos pelo codigo de barras ou codigo interno.
- Itens do XML sem produto vinculado devem aparecer na conferencia, sem serem ocultados.
- Importacao por planilha deve oferecer modelo Excel `.xlsx` para primeira carga/cadastro em massa.
- O modelo `.xlsx` deve vir com colunas sensiveis formatadas como texto, especialmente CNPJ/CPF, chave NF-e, codigo interno, codigo de barras, NCM e CFOP, para o Excel nao converter para notacao cientifica.
- A validade importada por planilha deve ser convertida para data pura `AAAA-MM-DD`, sem horario, mesmo quando o Excel salvar como data interna ou texto com hora.
- O modelo de planilha deve conter dados suficientes para cadastro e entrada: fornecedor, NF, codigo interno, codigo de barras, nome, unidade, quantidade, custo, preco de venda, estoque minimo, categoria, marca, NCM, CFOP, lote, validade e observacao.
- Ao importar planilha, produtos inexistentes podem ser criados automaticamente se o usuario tiver permissao de cadastro; caso contrario ficam pendentes para vinculo/conferencia.
- A conferencia de mercadoria deve exibir todos os itens da NF-e, quantidade da nota, quantidade recebida, unidade, custo, NCM, CFOP, lote, validade e status do item.
- Cada item pode ser aceito, marcado para cadastrar/vincular produto, marcado como pendencia/divergencia ou devolucao ao fornecedor.
- Somente itens aceitos, com produto vinculado e quantidade recebida maior que zero, entram no estoque e recalculam custo medio.
- Itens pendentes/devolucao devem ficar registrados na entrada para rastreabilidade, mas nao movimentam estoque.
- A validade e o lote podem vir do XML quando a NF-e trouxer rastreabilidade; caso contrario, devem ser informados manualmente na conferencia.
- O historico de estoque do produto deve exibir dados de recebimento quando a movimentacao vier de uma entrada: fornecedor, documento, NF/serie, lote, validade, quantidade recebida e observacao de conferencia.
- A entrada aceita cria ou soma saldo em `product_batches`, permitindo consulta de saldo por lote e validade no estoque.
- O fluxo deve ficar preparado para app mobile Android/iOS atuar como coletor, usando camera para ler codigo de barras durante a conferencia.
- A empresa cliente pode criar seus proprios usuarios dentro do tenant/link dela e liberar ou bloquear acoes especificas de entradas.
- Permissoes especificas do fluxo de entradas:
  - `stock:entries:view`: ver entradas e conferencias.
  - `stock:entries:create`: criar entrada manual, importar XML, importar planilha ou consultar chave.
  - `stock:entries:confirm`: confirmar conferencia e movimentar estoque.
  - `stock:entries:return`: marcar item para devolucao ao fornecedor.
  - `stock:entries:create_product_from_xml`: cadastrar produto a partir de XML ou planilha de entrada.
  - `stock:batches:view`: visualizar saldo por lote.
- Baixa automatica por chave da NF-e fica preparada para integracao futura com SEFAZ, exigindo certificado digital da empresa.
- Cada empresa/tenant deve ter seu proprio certificado digital configurado; certificado de uma empresa nunca deve servir para outra.

## Ordem de producao

- A ordem de producao usa a ficha tecnica do produto acabado.
- Ao concluir uma ordem:
  - o produto final recebe entrada no estoque;
  - os componentes da ficha tecnica recebem baixa automatica;
  - produtos controlados por lote baixam componentes pelo lote que vence primeiro;
  - a baixa considera quantidade produzida e percentual de perda;
  - todos os movimentos entram no historico de estoque.
- Produto sem ficha tecnica nao pode ser produzido pela ordem de producao.
- Servicos nao podem receber ordem de producao.

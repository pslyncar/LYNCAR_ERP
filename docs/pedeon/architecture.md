# Arquitetura do PedeOn

## Limites do produto

O PedeOn possui quatro superficies, conectadas pelo mesmo backend:

1. cardapio publico;
2. administracao e Central de pedidos no ERP;
3. recepcao, preparo e expedicao nos terminais autorizados;
4. controles comerciais e roteamento no Master Lyncar.

O cardapio publico deve ser uma aplicacao separada da interface autenticada do
ERP. O PDV Windows permanece no repositorio canonico
`C:\LYNCAR_PDV_APP_WINDOWS`. O backend compartilhado permanece em
`C:\erp_build\backend`.

## Dominios

- `catalog`: loja, categorias, publicacoes, disponibilidade e adicionais.
- `orders`: pedido, itens, snapshots, totais, estados e auditoria.
- `payments`: meios, tentativas, comprovacoes, reembolsos e idempotencia.
- `inventory`: reservas temporarias, efetivas, liberacao e consumo.
- `fulfillment`: estacoes, tarefas, preparo, separacao e expedicao.
- `delivery`: retirada, enderecos, areas, taxas e entrega.
- `terminals`: capacidades, receptor principal, reserva e heartbeat.
- `printing`: trabalhos duraveis, tentativas e confirmacao de impressao.
- `billing`: evento tarifavel e consolidacao da cobranca Lyncar.
- `channels`: adaptadores de entrada, origem imutavel, referencia externa e
  deduplicacao para PedeOn, salao, PDV e marketplaces.

Cada integracao com Venda, Estoque, Financeiro ou Fiscal deve usar um servico
de aplicacao explicito. Regras do PedeOn nao devem ser espalhadas pelas rotas
ou modelos atuais desses modulos.

## Portas de entrada e interfaces

O nucleo de pedidos nao conhece a interface que o originou. Cardapio PedeOn,
PedeOn Salao, QR de mesa, PDV de balcao, iFood e 99Food convertem seus dados no
mesmo comando de criacao. Origem e referencia externa acompanham pedido,
producao, impressao, venda, fiscal e relatorios.

O PDV Windows continua especializado em caixa e fiscal. Salao, cozinha e
entrega possuem clientes proprios, sobre a mesma API e o mesmo banco. Essa
separacao preserva a velocidade do caixa e evita duplicar regras.

## Persistencia e entrega

PostgreSQL e a fonte da verdade. Eventos que precisam chegar ao ERP, PDV, KDS,
impressora ou cobranca sao gravados junto com a operacao usando outbox
transacional. WebSocket apenas reduz latencia. Reconciliacao por cursor garante
recuperacao apos desconexao.

No futuro, a entrega da outbox pode usar RabbitMQ ou servico gerenciado sem
alterar o dominio ou os clientes, porque o contrato do evento permanece o
mesmo.

## Terminais

Nem todo PDV enxerga pedidos. Capacidades sao configuradas por terminal:

- visualizar;
- notificar;
- aceitar;
- preparar;
- expedir;
- cancelar;
- imprimir;
- receptor principal;
- receptor reserva.

As permissoes sao validadas no backend. Quando varios terminais podem operar,
controle de versao e transacao garantem que cada comando aconteca uma vez. Um
trabalho de impressao possui destino e chave idempotente para nao duplicar.

## Pagamento

### InfinitePay

O servidor cria o checkout e relaciona `order_nsu` ao pedido. Webhook e
consulta de confirmacao sao tratados de forma idempotente. O retorno do
navegador nunca comprova pagamento sozinho.

### Pix manual

O estabelecimento pode optar por cadastrar sua propria chave Pix em texto. O
PedeOn mostra a chave e orientacoes, mas nao afirma que houve pagamento. O
cliente informa que pagou e o pedido passa para `awaiting_manual_confirmation`.
Somente usuario ou terminal autorizado confirma ou recusa a conferencia.

A interface deve comunicar claramente que a confirmacao e manual e que o
estabelecimento precisa conferir a conta, evitando tratar comprovante enviado
como prova bancaria.

### Maquininha na entrega

Credito e debito sao configuracoes independentes da empresa. Essas opcoes so
podem aparecer quando o cliente escolhe entrega; a API repete a validacao para
impedir o uso em retirada. O pedido entra na fila operacional, enquanto o
pagamento permanece pendente ate um usuario autorizado registrar que recebeu
na maquininha. Criar ou aceitar o pedido nunca equivale a confirmar pagamento.

## Primeira fatia de pedidos

O checkout publico recalcula os itens no servidor e usa chave de idempotencia
para que cliques repetidos nao criem pedidos duplicados. Pedido, pagamento,
historico e evento de outbox sao persistidos separadamente. A Central de
Pedidos autenticada lista, detalha e conduz o pedido pelas transicoes validas.
Areas e taxas de entrega, rastreio publico e o feed incremental por cursor ja
fazem parte do contrato. O checkout reserva estoque com bloqueio transacional;
aceite/pagamento compromete, cancelamento libera e conclusao consome a reserva
de forma idempotente.

O contrato de terminal tambem reivindica trabalhos duraveis de impressao. Um
trabalho fica atribuido a um terminal por tentativa; sucesso encerra o job e
falha o devolve para a fila com espera progressiva. As telas PDV Caixa, Salao e
Cozinha/KDS permanecem clientes separados sobre esses mesmos contratos.

Ainda falta ligar os consumidores nas interfaces especializadas e fazer todos
os canais legados de estoque respeitarem a disponibilidade reservada global.

## Experiencia visual

O cardapio sera mobile-first, responsivo, acessivel e com identidade propria.
Views permanecem enxutas; ViewModels controlam estado; repositorios centralizam
dados; servicos encapsulam APIs. Dependencias Flutter so entram quando houver
ganho mensuravel e manutencao adequada.

O aplicativo publico vive em `C:\erp_build\pedeon_public_flutter`, separado do
Flutter administrativo. Ele usa rota limpa `/{public_slug}`, MVVM, repositorio
e servico HTTP. A primeira entrega possui busca, categorias, paginacao, grade
adaptativa, carrinho e conferencia do carrinho no servidor.

O navegador pode calcular um subtotal apenas para resposta imediata, mas esse
valor nunca e aceito como definitivo. O endpoint `quote` consulta novamente os
produtos publicados e resolve o preco na seguinte ordem: preco online
especifico, oferta canonica vigente quando habilitada, preco normal.
# Enderecamento publico

O cardápio usa `https://{public_slug}.lyncar.com.br/cardapio`. A tabela
`pedeon_public_stores` pertence ao banco Master e possui unicidade global tanto
para empresa quanto para slug. Os dados completos da loja continuam isolados
no tenant; o índice Master serve para reservar e rotear o endereço.

O salão não é um site público. O celular usa o Edge na rede local; o Edge
distribui os pedidos ao PDV PedeOn e ao ERP.

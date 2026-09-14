# Roadmap do PedeOn

As entregas sao incrementais, mas nenhuma fase usa estruturas descartaveis.

## Fase 1 - Fundacao

- arquitetura e contratos;
- estados de pedido e pagamento;
- modelos e migracoes;
- auditoria e outbox;
- ativacao no Master;
- configuracao por empresa e terminal;
- testes de concorrencia e idempotencia.

### Entregue ate 2026-08-22

- modelos, estados, outbox, registro de modulo e permissoes;
- API privada para loja, Pix manual, InfinitePay e terminais;
- tela responsiva `PedeOn by Lyncar` no ERP;
- validacao de dominio, testes unitarios e teste de widget.
- administracao do catalogo vinculada ao estoque, com categorias e publicacao
  individual;
- aplicativo Flutter publico separado, com rota por slug, busca, categorias,
  paginação, carrinho responsivo e cotacao segura no servidor.
- checkout publico idempotente, endereco estruturado e confirmacao do pedido;
- Central de Pedidos autenticada com detalhe, transicoes e auditoria;
- Pix manual, Pix InfinitePay e maquininha de credito/debito configuraveis
  separadamente pela empresa.

## Fase 2 - Catalogo e pedido

- publicacao sem duplicar produtos;
- categorias, adicionais e disponibilidade;
- cardapio publico profissional; **primeira entrega concluida**
- carrinho e cotacao calculada no servidor; **concluido**
- Central de pedidos no ERP; **primeira entrega concluida**
- entrega e retirada; **areas, taxas, minimo, frete gratis e previsao concluidos**

## Fase 3 - Pagamentos e estoque

- Pix manual com conferencia; **concluido**
- InfinitePay com webhook e consulta; **fluxo-base concluido**
- credito e debito na maquininha levada pelo entregador, com confirmacao do
  recebimento pelo estabelecimento; **concluido**
- reservas temporarias e efetivas; **motor concluido para pedidos PedeOn**
- expiracao e liberacao; **motor concluido; rotina recorrente ainda pendente**
- reembolso e auditoria;
- tarifa PedeOn configuravel pelo Master.

## Fase 4 - PDV, KDS e impressao

- terminais autorizados; **configuracao e contrato de API concluidos**
- receptor principal e reserva;
- sincronizacao incremental; **feed por cursor concluido; clientes pendentes**
- preparo por estacao;
- expedicao;
- impressao idempotente; **fila, claim e confirmacao concluidos**
- operacao sem roubar foco do caixa.

## Fase 5 - Fechamento ERP

- conversao unica em venda;
- financeiro;
- fiscal conforme politica;
- relatorios e monitoramento operacional.

## Evolucoes

- entregadores e roteirizacao avancada;
- campanhas, cupons e fidelidade;
- dominios personalizados;
- marketplaces;
- broker externo quando as metricas justificarem.

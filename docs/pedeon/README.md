# PedeOn by Lyncar

O PedeOn e o canal de pedidos online integrado ao Lyncar. O produto deve ser
construido por partes, mas sobre uma fundacao definitiva, auditavel e preparada
para varios segmentos, varios terminais e varias empresas.

## Documentos

- [Arquitetura](architecture.md)
- [Roadmap de implementacao](roadmap.md)
- [Ciclo de vida](order-lifecycle.md)

## Regras inegociaveis

- Pedido online nao e uma venda injetada no carrinho do PDV.
- O cadastro de produto do Lyncar continua sendo a fonte canonica.
- Publicacao no cardapio e configuracao do canal ficam separadas do produto.
- Estoque reservado e estoque baixado sao conceitos diferentes.
- WebSocket notifica; PostgreSQL e a fonte da verdade.
- Cada terminal recebe somente as capacidades PedeOn autorizadas.
- InfinitePay e Pix manual sao fluxos distintos.
- Interfaces nao podem roubar o foco da operacao de caixa.
- Cada dominio possui codigo, testes e contratos separados.
- A assinatura visual oficial e **PedeOn by Lyncar**.

## Aplicacoes

- Administracao autenticada: `admin_app/admin_flutter`.
- Cardapio publico: `pedeon_public_flutter`.
- API publica: `GET /pedeon/public/{slug}` e
  `POST /pedeon/public/{slug}/quote`.

O cardapio publico nunca recebe credenciais do ERP. O slug global identifica a
empresa no Master, e o servidor abre a conexao do tenant correspondente. Antes
do checkout, a cotacao e refeita no servidor para validar publicacao,
disponibilidade, vigencia da oferta e pedido minimo.

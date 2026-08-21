# PDV

## Objetivo

Modulo de ponto de venda para operacao de caixa, separado da tela administrativa de vendas.

## Regras principais

- O PDV deve abrir com codigo e senha/PIN de operador.
- O operador de PDV nao precisa ser usuario completo do ERP.
- O fiscal/supervisor de caixa autoriza acoes sensiveis por codigo e senha/PIN.
- Sangria e cancelamento de venda exigem autorizacao de fiscal/supervisor.
- Caixa aberto nao deve expirar por inatividade da sessao administrativa.
- A tela do PDV deve ter modo focado/tela cheia para uso em balcão/mercado.

## Implementacao atual

- Tela: `admin_app/admin_flutter/lib/screens/pdv_screen.dart`.
- Tela de vendas administrativa separada: `admin_app/admin_flutter/lib/screens/sales_screen.dart`.
- Cadastro de operadores/fiscais: `admin_app/admin_flutter/lib/screens/pdv_operators_screen.dart`.
- Modelo Flutter: `admin_app/admin_flutter/lib/models/pdv_operator.dart`.
- API: rotas em `backend/app/api/routes/pdv_operators.py`.
- Modelo backend: `backend/app/models/pdv_operator.py`.

## Endpoints relacionados

- `GET /pdv/operators`
- `POST /pdv/operators`
- `PUT /pdv/operators/{operator_id}`
- `POST /pdv/authorize`

## Evolucao futura

- Criar app separado de PDV para operador e fiscal de caixa.
- Esse app deve consumir a mesma API, mas autenticar o caixa por codigo/senha de operador em vez de exigir acesso completo ao ERP administrativo.
- Registrar abertura, sangria, fechamento e auditoria do caixa no banco de dados.

## Arquitetura fiscal e sincronizacao

- A fila local duravel do PDV e a fila fiscal transacional do backend sao a garantia de entrega.
- WebSocket apenas avisa sobre alteracoes; ao reconectar, o PDV sempre reconcilia pela API.
- Numeracao fiscal pertence ao backend e e serializada por empresa, ambiente, modelo e serie.
- A decisao completa e os criterios para uma futura migracao a RabbitMQ/servico gerenciado estao em [[2026-08-21 - Fila fiscal transacional e evolucao para broker]].

## Comprovante da venda

- Toda venda finalizada no PDV deve gerar um comprovante.
- Quando o Fiscal no PDV estiver pronto e ativo, o fluxo segue para NFC-e/DANFE.
- Quando o Fiscal no PDV estiver desligado ou indisponivel, o sistema gera automaticamente um `CUPOM NAO FISCAL`.
- O cupom nao fiscal deve exibir em destaque `NAO E DOCUMENTO FISCAL` e `Comprovante comercial sem valor fiscal`.
- O cupom nao fiscal possui empresa, venda, data, operador, itens, quantidades, precos, subtotal, desconto, total, pagamentos, valor recebido e troco.
- O cupom nao fiscal nao possui chave de acesso, protocolo SEFAZ, QR Code fiscal, serie/modelo fiscal ou texto que possa confundi-lo com NFC-e autorizada.

## Fechamento e tesouraria

- Ao fechar o caixa, o operador informa dinheiro contado e observacao quando houver sobra/falta.
- O fechamento vai para a tela Caixa/Tesouraria como `pending_treasury`.
- A tesouraria confere fundo, vendas por forma de pagamento, sangrias/suprimentos, dinheiro esperado, contado e diferenca.
- A tesouraria pode aprovar o fechamento ou marcar divergencia com observacao.

Arquivos envolvidos:

- `backend/app/api/routes/cash_closings.py`
- `backend/app/models/cash_closing.py`
- `backend/app/schemas/cash_closing.py`
- `admin_app/admin_flutter/lib/screens/cash_closings_screen.dart`
- `admin_app/admin_flutter/lib/models/cash_closing.dart`

Endpoints:

- `POST /pdv/closings`
- `GET /pdv/closings`
- `PUT /pdv/closings/{closing_id}/treasury-review`

## Responsividade

- A tela do PDV deve ser responsiva: em monitores largos, leitura de produtos e venda atual ficam lado a lado; em telas menores, os blocos devem empilhar e permitir rolagem sem cortar botoes, totais ou campos.
- Implementacao no Flutter usa `LayoutBuilder`, `ListView`, `SingleChildScrollView` e cabecalho adaptavel.
- O cabecalho do PDV quebra os botoes de acao para uma segunda linha com rolagem horizontal quando a largura nao comporta tudo.

## Operacao por atalhos

- O fluxo de PDV deve priorizar comandos de teclado, similar a caixas de mercado.
- Atalhos atuais no app administrativo:
  - `F2`: focar leitura/codigo do produto.
  - `F4`: aplicar desconto com autorizacao fiscal.
  - `F5`: cancelar item com autorizacao fiscal.
  - `F6`: abrir pagamento/finalizacao.
  - `F9`: cancelar venda com autorizacao fiscal.
- A venda atual mostra resumo e total; a forma de pagamento e valor recebido ficam em tela separada de pagamento, aberta pelo comando de finalizacao.
- No Flutter Web, o `web/index.html` bloqueia a acao padrao do navegador para `F2`, `F4`, `F5`, `F6` e `F9`, permitindo que esses atalhos sejam tratados pelo app sem recarregar pagina ou focar a barra de endereco.
- A tela PDV usa `HardwareKeyboard.instance.addHandler` para capturar atalhos no nivel global do app enquanto o caixa esta aberto, evitando depender do foco em um campo especifico.

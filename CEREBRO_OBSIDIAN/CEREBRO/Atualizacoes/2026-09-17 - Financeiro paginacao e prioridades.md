# 2026-09-17 - Financeiro: paginação e prioridades

## Carteira de clientes

- Mantida a paginação de **50 clientes por página**.
- Os controles de primeira, anterior, próxima e última página agora aparecem
  antes e depois da carteira; não é mais necessário chegar ao rodapé da lista
  para descobrir que existem outros clientes.
- O cabeçalho da carteira informa a quantidade exibida e o total, por exemplo:
  `50 de 137 cliente(s)`.

## Prioridades de hoje

- Todos os clientes com títulos vencidos permanecem acessíveis.
- A lista passa a ter rolagem interna, limitada visualmente para não esticar ou
  desmontar o painel quando houver muitos alertas.
- Removido o comportamento que escondia alertas após três itens.

## Validação

- `dart format lib/screens/finance_screen.dart`
- `flutter analyze lib/screens/finance_screen.dart`
- Nenhum diagnóstico reportado para a tela alterada.

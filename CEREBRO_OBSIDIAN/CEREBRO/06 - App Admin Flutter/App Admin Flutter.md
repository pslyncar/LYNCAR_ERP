# App Admin Flutter

Aplicativo administrativo usado por administradores, tecnicos, vendedores, operadores de caixa e outros colaboradores conforme permissoes.

## Caminho

```text
C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\admin_app\admin_flutter
```

## Tecnologias encontradas

Arquivo: `admin_app/admin_flutter/pubspec.yaml`

- Flutter.
- Dart SDK `^3.12.0`.
- Material Icons.
- `http: ^1.6.0`.
- `flutter_lints: ^6.0.0`.
- Assets de marca em `assets/brand`.

## Estrutura principal

- `lib/main.dart`
- `lib/app.dart`
- `lib/screens`
- `lib/models`
- `lib/services`
- `lib/widgets`
- `lib/utils`

## Autenticacao e sessao

Arquivo: `lib/app.dart`.

- `AuthGate` restaura sessao salva.
- Chaves de armazenamento:
  - `papezzosync.session`
  - `papezzosync.lastActivity`
- Sessao expira por inatividade depois de 10 minutos.
- Sessao tambem expira se o token estiver expirado.
- Quando nao ha sessao valida, abre `LoginScreen`.
- Quando ha sessao valida, abre `AppShell`.
- Quando existe caixa PDV aberto, o app mantem a atividade viva e nao encerra a sessao por inatividade.
- Ao fechar o caixa PDV, a expiracao normal por inatividade volta a valer.

## Navegacao por permissoes

Arquivo: `lib/screens/app_shell.dart`.

O menu lateral mostra destinos conforme `session.can(...)`:

- Dashboard: `dashboard:view`.
- Clientes: `clients:view`.
- Maquinas: `equipments:view` ou `monitoring:view`.
- OS: `service_orders:view`.
- Vendas: `sales:view`.
- PDV: `sales:create`.
- Caixa: `sales:view`.
- Financeiro: `finance:view`, `finance:receivables:view` ou `finance:payables:view`.
- Produtos: `products:view` ou `stock:view`.
- Entradas: `stock:entries:view`, `stock:entries:create` ou `stock:entries:confirm`.
- Fornecedores: `suppliers:view`, `suppliers:create` ou `suppliers:update`.
- Producao: `production:view` ou `production:create`.
- Op. PDV: `pdv_operators:manage`.
- Usuarios: `users:manage`.
- Configuracoes: aparece para usuarios de empresas/tenants como area geral de parametros do sistema.

O modulo Fiscal nao fica mais como item direto do menu lateral. Ele fica dentro de `Configuracoes`, porque certificado A1, CSC/ID e parametros NFC-e/NF-e sao ajustes estruturais da empresa, nao uma operacao diaria do ERP. A opcao Fiscal dentro de Configuracoes so aparece quando a empresa/usuario tiver acesso fiscal liberado pelo master, usando `fiscal:view`, `fiscal:settings` ou `fiscal:documents:view`.

Se o usuario nao tiver acessos liberados, o app mostra mensagem de usuario sem acessos e botao de sair.

## Telas encontradas

Arquivos em `lib/screens`:

- `login_screen.dart`
- `companies_screen.dart`
- `dashboard_screen.dart`
- `clients_screen.dart`
- `equipments_screen.dart`
- `service_orders_screen.dart`
- `sales_screen.dart`
- `pdv_screen.dart`
- `cash_closings_screen.dart`
- `finance_screen.dart`
- `products_screen.dart`
- `stock_entries_screen.dart`
- `suppliers_screen.dart`
- `production_orders_screen.dart`
- `fiscal_screen.dart`
- `settings_screen.dart`
- `pdv_operators_screen.dart`
- `users_screen.dart`
- `app_shell.dart`

## Modelos encontrados

Arquivos em `lib/models`:

- Cliente.
- Dashboard summary.
- Equipamento.
- Status atual de equipamento.
- Snapshot de monitoramento.
- Operador PDV.
- Produto.
- Venda.
- Ordem de servico.
- Sessao.
- Usuario do sistema.

## Cliente de API

Arquivo: `lib/services/api_client.dart`.

Endpoints consumidos pelo app:

- `/auth/login`
- `/auth/me`
- `/master/companies`
- `/dashboard/summary`
- `/clients`
- `/equipments`
- `/equipments/{equipment_id}/agent-token`
- `/monitoring/snapshots`
- `/monitoring/current-status`
- `/monitoring/alerts`
- `/products`
- `/products/lookup/by-code`
- `/sales`
- `/sales/{sale_id}/cancel`
- `/admin/users`
- `/admin/roles`
- `/admin/permissions`
- `/admin/users/{user_id}/permissions`
- `/pdv/operators`
- `/pdv/authorize`
- `/service-orders`
- `/service-orders/{service_order_id}/items`
- `/service-orders/{service_order_id}/thermal-print`

## Impressao

Arquivos:

- `lib/services/receipt_print.dart`
- `lib/services/receipt_print_web.dart`
- `lib/services/receipt_print_stub.dart`
- `lib/services/fiscal_print.dart`
- `lib/services/fiscal_print_web.dart`
- `lib/services/fiscal_print_stub.dart`

O app possui suporte web para gerar recibo HTML e chamar `window.print()`. Tambem consome endpoint de impressao termica de OS no backend.
Para documentos fiscais, o app abre o PDF do DANFE em iframe oculto e aciona a impressao do navegador. O PDF fiscal vem do backend em `/fiscal/documents/{id}/danfe`.

## Notas fiscais

- Configuracoes fiscais permanecem em `lib/screens/fiscal_screen.dart`.
- A operacao diaria usa `lib/screens/fiscal_documents_screen.dart`.
- A tela operacional lista NFC-e/NF-e, pesquisa, filtra, mostra resumo por status e abre detalhes.
- NFC-e pode ser preparada a partir de venda finalizada e enviada ao motor modelo 65.
- NF-e modelo 55 pode ser preparada a partir de venda finalizada e enviada ao motor modelo 55.
- A tela imprime DANFE PDF para NFC-e/NF-e autorizada ou cancelada.
- Cancelamento usa evento real da SEFAZ e so muda status local quando a SEFAZ aceita.
- A tela nunca simula cancelamento alterando apenas o status local.

## Vendas e PDV

Arquivos principais:

- Vendas administrativas: `lib/screens/sales_screen.dart`.
- PDV de caixa: `lib/screens/pdv_screen.dart`.

- Vendas e PDV ficam em entradas separadas no menu para evitar misturar o fluxo administrativo da assistencia com o fluxo de caixa de comercio.
- Para abrir caixa, solicita codigo do operador, senha/PIN e fundo de caixa.
- O codigo do operador e validado pela API `/pdv/authorize`.
- Acoes sensiveis como sangria e cancelamento solicitam autorizacao de fiscal/supervisor.
- A tela possui opcao de modo focado/tela cheia, escondendo a navegacao lateral do ERP enquanto o caixa esta em operacao.
- O modo tela cheia atual e dentro do app Flutter; um app separado de PDV ainda e decisao/implementacao futura.
- A navegacao lateral do app foi substituida por menu proprio com rolagem interna e botao Sair fixo no rodape, evitando que destinos novos espremam o menu em telas menores.
- O PDV usa `LayoutBuilder`, `ListView` e `SingleChildScrollView` para adaptar o caixa: em tela larga fica em duas colunas; em tela estreita/baixa empilha leitura de produtos e venda atual com rolagem.
- O cabecalho do PDV quebra os botoes de acao para uma segunda linha com rolagem horizontal quando a largura nao comporta tudo.
- O PDV possui barra inferior de comandos por atalhos (`F2`, `F4`, `F5`, `F6`, `F9`) e a finalizacao abre tela de pagamento separada.

## Comando para rodar

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\admin_app\admin_flutter
C:\Users\vpape\Documents\DevTools\flutter\bin\flutter.bat run -d web-server --web-hostname 127.0.0.1 --web-port 5000
```

## Nao determinado

- README interno do Flutter ainda esta com texto padrao de projeto novo.
- Nao foi encontrado app separado para cliente final.

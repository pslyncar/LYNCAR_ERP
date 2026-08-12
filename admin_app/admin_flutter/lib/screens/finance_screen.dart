import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/payable.dart';
import '../models/receivable.dart';
import '../models/session.dart';
import '../models/supplier.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, required this.session});

  final Session session;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Client> _clients = [];
  List<Receivable> _receivables = [];
  List<Supplier> _suppliers = [];
  List<Payable> _payables = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listClients(widget.session.token),
        _api.listReceivables(widget.session.token, limit: 500),
        _api.listSuppliers(widget.session.token),
        _api.listPayables(widget.session.token, limit: 500),
      ]);
      setState(() {
        _clients = results[0] as List<Client>;
        _receivables = results[1] as List<Receivable>;
        _suppliers = results[2] as List<Supplier>;
        _payables = results[3] as List<Payable>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar o financeiro.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openStatement(_ClientReceivables account) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClientStatementDialog(
        api: _api,
        token: widget.session.token,
        account: account,
        canPay: widget.session.can('finance:receivables:pay'),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openManualReceivable() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ManualReceivableDialog(
        api: _api,
        token: widget.session.token,
        clients: _clients,
      ),
    );
    if (changed == true) {
      setState(() => _tab = 0);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _filteredAccounts();
    final openReceivables = _receivables
        .where((item) => item.balanceAmount > 0.009)
        .toList();
    final openBalance = openReceivables.fold<double>(
      0,
      (sum, item) => sum + item.balanceAmount,
    );
    final paidAmount = _receivables.fold<double>(
      0,
      (sum, item) => sum + item.paidAmount,
    );
    final overdue = openReceivables.where((item) {
      final due = item.dueDate;
      if (due == null) return false;
      return due.isBefore(DateTime.now());
    }).length;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Financeiro',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Contas a receber, crediario e conferência financeira',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
                if (widget.session.can('finance:receivables:pay')) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _openManualReceivable,
                    icon: const Icon(Icons.add),
                    label: const Text('Lançar crediário'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 920 ? 4 : 2;
                final cards = [
                  _Summary(
                    'A receber',
                    openBalance,
                    Icons.account_balance_wallet_outlined,
                    money: true,
                  ),
                  _Summary(
                    'Clientes com saldo',
                    accounts.where((item) => item.balance > 0.009).length,
                    Icons.people_alt_outlined,
                  ),
                  _Summary(
                    'Recebido',
                    paidAmount,
                    Icons.payments_outlined,
                    money: true,
                  ),
                  _Summary('Vencidos', overdue, Icons.warning_amber_outlined),
                ];
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 98,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) =>
                      _SummaryTile(summary: cards[index]),
                );
              },
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente ou venda',
                        hintText: 'Nome, documento, e-mail, CR ou venda...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    selected: {_tab},
                    onSelectionChanged: (value) =>
                        setState(() => _tab = value.first),
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('A receber'),
                        icon: Icon(Icons.call_received),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('A pagar'),
                        icon: Icon(Icons.call_made),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else if (_tab == 0)
              _ReceivablesByClient(accounts: accounts, onOpen: _openStatement)
            else
              _PayablesPanel(
                payables: _filteredPayables(),
                suppliers: _suppliers,
                canManage: widget.session.can('finance:payables:manage'),
                onChanged: _load,
                api: _api,
                token: widget.session.token,
              ),
          ],
        ),
      ),
    );
  }

  List<_ClientReceivables> _filteredAccounts() {
    final clientById = {for (final client in _clients) client.id: client};
    final grouped = <int, List<Receivable>>{};
    final withoutClient = <Receivable>[];
    for (final receivable in _receivables) {
      if (receivable.clientId == null) {
        withoutClient.add(receivable);
      } else {
        grouped.putIfAbsent(receivable.clientId!, () => []).add(receivable);
      }
    }

    final accounts = [
      for (final entry in grouped.entries)
        _ClientReceivables(
          client: clientById[entry.key],
          fallbackName: entry.value.first.clientName ?? 'Cliente #${entry.key}',
          receivables: entry.value,
        ),
      if (withoutClient.isNotEmpty)
        _ClientReceivables(
          fallbackName: 'Consumidor final / sem cadastro',
          receivables: withoutClient,
        ),
    ];
    accounts.sort((a, b) => b.balance.compareTo(a.balance));

    final term = _normalize(_search.text);
    if (term.isEmpty) return accounts;
    return accounts.where((account) {
      final haystack = _normalize(
        [
          account.name,
          account.client?.documentNumber,
          account.client?.email,
          for (final receivable in account.receivables) ...[
            receivable.number,
            receivable.saleNumber,
            receivable.description,
          ],
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }

  List<Payable> _filteredPayables() {
    final term = _normalize(_search.text);
    final items = [..._payables];
    items.sort((a, b) {
      final dueA = a.dueDate;
      final dueB = b.dueDate;
      if (dueA == null && dueB == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (dueA == null) return 1;
      if (dueB == null) return -1;
      return dueA.compareTo(dueB);
    });
    if (term.isEmpty) return items;
    return items.where((payable) {
      final haystack = _normalize(
        [
          payable.number,
          payable.supplierName,
          payable.description,
          payable.documentNumber,
          payable.category,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }
}

class _ManualReceivableDialog extends StatefulWidget {
  const _ManualReceivableDialog({
    required this.api,
    required this.token,
    required this.clients,
  });

  final ApiClient api;
  final String token;
  final List<Client> clients;

  @override
  State<_ManualReceivableDialog> createState() =>
      _ManualReceivableDialogState();
}

class _ManualReceivableDialogState extends State<_ManualReceivableDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController(
    text: 'Lançamento manual de crediário',
  );
  final _dueDate = TextEditingController();
  final _notes = TextEditingController();
  Client? _client;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _dueDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _clientLabel(Client client) {
    final doc = client.documentNumber;
    if (doc == null || doc.trim().isEmpty) return client.name;
    return '${client.name} • $doc';
  }

  DateTime? _parseDate(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) return null;
    final day = int.tryParse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(2, 4));
    final year = int.tryParse(digits.substring(4, 8));
    if (day == null || month == null || year == null) return null;
    final parsed = DateTime(year, month, day, 12);
    if (parsed.day != day || parsed.month != month || parsed.year != year) {
      return null;
    }
    return parsed;
  }

  Future<void> _save() async {
    final client = _client;
    final amount = parseBrazilianNumber(_amount.text);
    if (client == null) {
      setState(() => _error = 'Selecione o cliente.');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = 'Informe o valor do crediário.');
      return;
    }
    final dueText = _dueDate.text.trim();
    final dueDate = dueText.isEmpty ? null : _parseDate(dueText);
    if (dueText.isNotEmpty && dueDate == null) {
      setState(() => _error = 'Informe uma data de vencimento válida.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.createManualReceivable(
        widget.token,
        ReceivableManualPayload(
          clientId: client.id,
          amount: amount,
          description: _description.text,
          dueDate: dueDate,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível lançar o crediário.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lançar crediário'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Use para cadastrar saldo antigo do caderno sem criar venda e sem mexer no estoque.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Autocomplete<Client>(
                displayStringForOption: _clientLabel,
                optionsBuilder: (value) {
                  final term = _normalize(value.text);
                  if (term.isEmpty) return widget.clients.take(20);
                  return widget.clients
                      .where((client) {
                        final haystack = _normalize(
                          [
                            client.name,
                            client.tradeName,
                            client.documentNumber,
                            client.email,
                            client.phone,
                            client.mobilePhone,
                          ].whereType<String>().join(' '),
                        );
                        return haystack.contains(term);
                      })
                      .take(30);
                },
                onSelected: (client) => setState(() => _client = client),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      if (_client != null &&
                          controller.text != _clientLabel(_client!)) {
                        controller.text = _clientLabel(_client!);
                      }
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Cliente',
                          hintText: 'Digite o nome, CPF/CNPJ ou telefone',
                          prefixIcon: Icon(Icons.person_search_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (_client != null) {
                            setState(() => _client = null);
                          }
                        },
                      );
                    },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianMoneyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        prefixText: r'R$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dueDate,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianDateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Vencimento',
                        hintText: 'dd/mm/aaaa',
                        prefixIcon: Icon(Icons.event_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  hintText: 'Ex.: saldo antigo do caderno',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Salvando...' : 'Salvar crediário'),
        ),
      ],
    );
  }
}

class _ReceivablesByClient extends StatelessWidget {
  const _ReceivablesByClient({required this.accounts, required this.onOpen});

  final List<_ClientReceivables> accounts;
  final ValueChanged<_ClientReceivables> onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: accounts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma conta a receber encontrada.'),
            )
          : ResponsiveDataTable(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Títulos')),
                  DataColumn(label: Text('Original')),
                  DataColumn(label: Text('Recebido')),
                  DataColumn(label: Text('Saldo')),
                  DataColumn(label: Text('Crédito')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: [
                  for (final account in accounts)
                    DataRow(
                      onSelectChanged: (_) => onOpen(account),
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 280,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  account.client?.documentNumber ??
                                      account.client?.email ??
                                      '-',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text('${account.openCount} aberto(s)')),
                        DataCell(Text(_money(account.original))),
                        DataCell(Text(_money(account.paid))),
                        DataCell(
                          Text(
                            _money(account.balance),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        DataCell(Text(_creditLabel(account.client))),
                        DataCell(
                          IconButton(
                            tooltip: 'Abrir extrato',
                            onPressed: () => onOpen(account),
                            icon: const Icon(Icons.receipt_long_outlined),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _ClientStatementDialog extends StatefulWidget {
  const _ClientStatementDialog({
    required this.api,
    required this.token,
    required this.account,
    required this.canPay,
  });

  final ApiClient api;
  final String token;
  final _ClientReceivables account;
  final bool canPay;

  @override
  State<_ClientStatementDialog> createState() => _ClientStatementDialogState();
}

class _ClientStatementDialogState extends State<_ClientStatementDialog> {
  Future<bool> _pay(Receivable receivable) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ReceivablePaymentDialog(
        api: widget.api,
        token: widget.token,
        receivable: receivable,
      ),
    );
    return changed == true;
  }

  Future<bool> _payAccount() async {
    final clientId = widget.account.client?.id;
    if (clientId == null) return false;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClientPaymentDialog(
        api: widget.api,
        token: widget.token,
        account: widget.account,
      ),
    );
    return changed == true;
  }

  Future<bool> _cancelReceivable(Receivable receivable) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar ${receivable.number ?? 'CR${receivable.id}'}?'),
        content: const Text(
          'Este crediario sera marcado como cancelado e deixara de aparecer como saldo em aberto. O historico sera mantido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar crediario'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await widget.api.cancelReceivable(widget.token, receivable.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final statementEntries = _statementEntries(account.receivables);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extrato de ${account.name}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Saldo ${_money(account.balance)} | recebido ${_money(account.paid)}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                  if (widget.canPay &&
                      account.client != null &&
                      account.balance > 0.009) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final changed = await _payAccount();
                        if (!mounted) return;
                        if (changed) navigator.pop(true);
                      },
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Receber do cliente'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in statementEntries)
                        _buildStatementEntry(context, entry),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatementEntry(BuildContext context, _StatementEntry entry) {
    if (entry.isSaleGroup) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(
              'Venda ${entry.saleNumber} - ${entry.receivables.length} parcelas',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(_saleGroupSubtitle(entry)),
            trailing: Text(
              'Saldo ${_money(entry.balanceAmount)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            children: [
              _SaleGroupSummary(entry: entry),
              const SizedBox(height: 10),
              _SaleItems(items: entry.first.saleItems),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Parcelas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final receivable in entry.receivables)
                _buildInstallmentRow(context, receivable),
            ],
          ),
        ),
      );
    }

    final receivable = entry.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: Text(
            _receivableStatementTitle(receivable),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(_receivableStatementSubtitle(receivable)),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _receivableBalanceLabel(receivable),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (widget.canPay && receivable.balanceAmount > 0.009)
                FilledButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final changed = await _pay(receivable);
                    if (!mounted) return;
                    if (changed) navigator.pop(true);
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Baixar'),
                ),
              if (widget.canPay && receivable.balanceAmount > 0.009)
                IconButton(
                  tooltip: 'Cancelar crediario',
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final changed = await _cancelReceivable(receivable);
                    if (!mounted) return;
                    if (changed) navigator.pop(true);
                  },
                  icon: const Icon(Icons.cancel_outlined),
                ),
            ],
          ),
          children: [
            _ReceivableSaleSummary(receivable: receivable),
            const SizedBox(height: 10),
            _StatementAmounts(receivable: receivable),
            const SizedBox(height: 10),
            _SaleItems(items: receivable.saleItems),
            const SizedBox(height: 10),
            _PaymentHistory(payments: receivable.payments),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallmentRow(BuildContext context, Receivable receivable) {
    final installment = _installmentInfo(receivable.description);
    final title = installment == null
        ? receivable.number ?? 'CR${receivable.id}'
        : '${receivable.number ?? 'CR${receivable.id}'} - parcela ${installment.current}/${installment.total}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text('Vence ${_date(receivable.dueDate)}'),
          ),
          SizedBox(width: 120, child: Text(_statusLabel(receivable.status))),
          SizedBox(
            width: 140,
            child: Text(
              'Saldo ${_money(receivable.balanceAmount)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (widget.canPay && receivable.balanceAmount > 0.009)
            FilledButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final changed = await _pay(receivable);
                if (!mounted) return;
                if (changed) navigator.pop(true);
              },
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Baixar'),
            ),
          if (widget.canPay && receivable.balanceAmount > 0.009)
            IconButton(
              tooltip: 'Cancelar parcela',
              onPressed: () async {
                final navigator = Navigator.of(context);
                final changed = await _cancelReceivable(receivable);
                if (!mounted) return;
                if (changed) navigator.pop(true);
              },
              icon: const Icon(Icons.cancel_outlined),
            ),
        ],
      ),
    );
  }
}

class _ClientPaymentDialog extends StatefulWidget {
  const _ClientPaymentDialog({
    required this.api,
    required this.token,
    required this.account,
  });

  final ApiClient api;
  final String token;
  final _ClientReceivables account;

  @override
  State<_ClientPaymentDialog> createState() => _ClientPaymentDialogState();
}

class _ClientPaymentDialogState extends State<_ClientPaymentDialog> {
  late final _amount = TextEditingController(
    text: formatBrazilianMoneyInput(widget.account.balance),
  );
  final _notes = TextEditingController();
  String _method = 'dinheiro';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final clientId = widget.account.client?.id;
    final amount = parseBrazilianNumber(_amount.text);
    final amountCents = _toMoneyCents(amount);
    final balanceCents = _toMoneyCents(widget.account.balance);
    if (clientId == null) {
      setState(() => _error = 'Cliente cadastrado obrigatorio.');
      return;
    }
    if (amountCents <= 0) {
      setState(() => _error = 'Informe o valor recebido.');
      return;
    }
    if (amountCents > balanceCents) {
      setState(() => _error = 'Valor maior que o saldo em aberto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.payClientReceivables(
        widget.token,
        clientId,
        ReceivablePaymentPayload(
          amount: amount,
          method: _method,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível registrar o recebimento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseBrazilianNumber(_amount.text);
    final remaining = (widget.account.balance - amount)
        .clamp(0, double.infinity)
        .toDouble();
    return AlertDialog(
      title: Text('Receber de ${widget.account.name}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewLine('Saldo total', widget.account.balance, strong: true),
            _ReviewLine('Saldo após recebimento', remaining),
            const SizedBox(height: 10),
            const Text(
              'O valor será aplicado automaticamente nos títulos vencidos/mais antigos primeiro.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.text,
              inputFormatters: const [BrazilianMoneyInputFormatter()],
              onTap: () => _amount.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _amount.text.length,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor recebido',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Forma de recebimento',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                DropdownMenuItem(value: 'pix', child: Text('Pix')),
                DropdownMenuItem(value: 'debito', child: Text('Débito')),
                DropdownMenuItem(value: 'credito', child: Text('Crédito')),
                DropdownMenuItem(
                  value: 'transferencia',
                  child: Text('Transferência'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _method = value ?? 'dinheiro'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_saving ? 'Salvando...' : 'Confirmar recebimento'),
        ),
      ],
    );
  }
}

class _ReceivablePaymentDialog extends StatefulWidget {
  const _ReceivablePaymentDialog({
    required this.api,
    required this.token,
    required this.receivable,
  });

  final ApiClient api;
  final String token;
  final Receivable receivable;

  @override
  State<_ReceivablePaymentDialog> createState() =>
      _ReceivablePaymentDialogState();
}

class _ReceivablePaymentDialogState extends State<_ReceivablePaymentDialog> {
  late final _amount = TextEditingController(
    text: formatBrazilianMoneyInput(widget.receivable.balanceAmount),
  );
  final _notes = TextEditingController();
  String _method = 'dinheiro';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseBrazilianNumber(_amount.text);
    final amountCents = _toMoneyCents(amount);
    final balanceCents = _toMoneyCents(widget.receivable.balanceAmount);
    if (amountCents <= 0) {
      setState(() => _error = 'Informe o valor recebido.');
      return;
    }
    if (amountCents > balanceCents) {
      setState(() => _error = 'Valor maior que o saldo em aberto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.payReceivable(
        widget.token,
        widget.receivable.id,
        ReceivablePaymentPayload(
          amount: amount,
          method: _method,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível registrar o recebimento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseBrazilianNumber(_amount.text);
    final remaining = (widget.receivable.balanceAmount - amount)
        .clamp(0, double.infinity)
        .toDouble();
    return AlertDialog(
      title: const Text('Registrar recebimento'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewLine(
              'Saldo em aberto',
              widget.receivable.balanceAmount,
              strong: true,
            ),
            _ReviewLine('Saldo após baixa', remaining),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.text,
              inputFormatters: const [BrazilianMoneyInputFormatter()],
              onTap: () => _amount.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _amount.text.length,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor recebido',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Forma de recebimento',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                DropdownMenuItem(value: 'pix', child: Text('Pix')),
                DropdownMenuItem(value: 'debito', child: Text('Débito')),
                DropdownMenuItem(value: 'credito', child: Text('Crédito')),
                DropdownMenuItem(
                  value: 'transferencia',
                  child: Text('Transferência'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _method = value ?? 'dinheiro'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_saving ? 'Salvando...' : 'Confirmar baixa'),
        ),
      ],
    );
  }
}

class _StatementEntry {
  const _StatementEntry(this.receivables);

  final List<Receivable> receivables;

  Receivable get first => receivables.first;

  bool get isSaleGroup => first.saleId != null && receivables.length > 1;

  String get saleNumber => first.saleNumber ?? 'V${first.saleId}';

  double get originalAmount =>
      receivables.fold(0, (sum, item) => sum + item.originalAmount);

  double get paidAmount =>
      receivables.fold(0, (sum, item) => sum + item.paidAmount);

  double get balanceAmount =>
      receivables.fold(0, (sum, item) => sum + item.balanceAmount);

  double get saleTotal {
    final itemsTotal = first.saleItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    return itemsTotal > 0.009 ? itemsTotal : originalAmount;
  }

  DateTime get sortDate => first.saleSoldAt ?? first.createdAt;
}

List<_StatementEntry> _statementEntries(List<Receivable> receivables) {
  final saleGroups = <int, List<Receivable>>{};
  final entries = <_StatementEntry>[];

  for (final receivable in receivables) {
    final saleId = receivable.saleId;
    if (saleId == null) {
      entries.add(_StatementEntry([receivable]));
      continue;
    }
    saleGroups.putIfAbsent(saleId, () => []).add(receivable);
  }

  for (final group in saleGroups.values) {
    group.sort(_compareInstallments);
    entries.add(_StatementEntry(group));
  }

  entries.sort((a, b) => b.sortDate.compareTo(a.sortDate));
  return entries;
}

int _compareInstallments(Receivable a, Receivable b) {
  final aInstallment = _installmentInfo(a.description);
  final bInstallment = _installmentInfo(b.description);
  final aOrder = aInstallment?.current ?? 0;
  final bOrder = bInstallment?.current ?? 0;
  if (aOrder != bOrder) return aOrder.compareTo(bOrder);
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null) return aDue.compareTo(bDue);
  if (aDue != null) return -1;
  if (bDue != null) return 1;
  return a.id.compareTo(b.id);
}

String _saleGroupSubtitle(_StatementEntry entry) {
  final method = _methodFromReceivableDescription(entry.first.description);
  final parts = <String>[
    _dateTime(entry.sortDate),
    '${entry.receivables.length} parcelas',
    _statusLabel(_saleGroupStatus(entry)),
  ];
  if (method != null) parts.add(method);
  return parts.join(' | ');
}

String _saleGroupStatus(_StatementEntry entry) {
  if (entry.receivables.every((item) => item.status == 'paid')) {
    return 'paid';
  }
  if (entry.receivables.every((item) => item.status == 'canceled')) {
    return 'canceled';
  }
  if (entry.paidAmount > 0.009) return 'partial';
  return 'open';
}

class _SaleGroupSummary extends StatelessWidget {
  const _SaleGroupSummary({required this.entry});

  final _StatementEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Venda ${entry.saleNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Chip(
                label: Text('${entry.receivables.length} parcelas'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _StatementTextLine('Total da venda', _money(entry.saleTotal)),
          _StatementTextLine('Total parcelado', _money(entry.originalAmount)),
          _StatementTextLine('Recebido', _money(entry.paidAmount)),
          _StatementTextLine('Saldo em aberto', _money(entry.balanceAmount)),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'A venda é única. As parcelas abaixo são os títulos financeiros para baixa por vencimento.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementAmounts extends StatelessWidget {
  const _StatementAmounts({required this.receivable});

  final Receivable receivable;

  @override
  Widget build(BuildContext context) {
    final installment = _installmentInfo(receivable.description);
    return Column(
      children: [
        _ReviewLine(
          installment == null ? 'Valor original' : 'Valor da parcela',
          receivable.originalAmount,
        ),
        _ReviewLine('Recebido', receivable.paidAmount),
        _ReviewLine(
          installment == null ? 'Saldo' : 'Saldo da parcela',
          receivable.balanceAmount,
          strong: true,
        ),
      ],
    );
  }
}

class _ReceivableSaleSummary extends StatelessWidget {
  const _ReceivableSaleSummary({required this.receivable});

  final Receivable receivable;

  @override
  Widget build(BuildContext context) {
    final saleTotal = receivable.saleItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    final installment = _installmentInfo(receivable.description);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  receivable.saleNumber == null
                      ? receivable.description
                      : 'Venda ${receivable.saleNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (installment != null)
                Chip(
                  label: Text(
                    'Parcela ${installment.current}/${installment.total}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _StatementTextLine(
            'Título em aberto',
            '${receivable.number ?? 'CR${receivable.id}'} - ${_money(receivable.originalAmount)}',
          ),
          if (receivable.dueDate != null)
            _StatementTextLine('Vencimento', _date(receivable.dueDate)),
          if (saleTotal > 0.009)
            _StatementTextLine('Total da venda', _money(saleTotal)),
          if (installment != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Os itens abaixo pertencem à venda completa. O valor deste título é somente a parcela selecionada.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatementTextLine extends StatelessWidget {
  const _StatementTextLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SaleItems extends StatelessWidget {
  const _SaleItems({required this.items});

  final List<ReceivableSaleItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Itens da venda não encontrados.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Itens comprados',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(item.description)),
                Text('${formatBrazilianDecimal(item.quantity)} ${item.unit}'),
                const SizedBox(width: 16),
                Text(
                  _money(item.totalPrice),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentHistory extends StatelessWidget {
  const _PaymentHistory({required this.payments});

  final List<ReceivablePayment> payments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Baixas / recebimentos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        if (payments.isEmpty)
          const Text('Nenhum recebimento registrado.')
        else
          for (final payment in payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_paymentLabel(payment.method)} - ${_dateTime(payment.paidAt)}',
                    ),
                  ),
                  Text(
                    _money(payment.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _PayablesPanel extends StatelessWidget {
  const _PayablesPanel({
    required this.payables,
    required this.suppliers,
    required this.canManage,
    required this.onChanged,
    required this.api,
    required this.token,
  });

  final List<Payable> payables;
  final List<Supplier> suppliers;
  final bool canManage;
  final Future<void> Function() onChanged;
  final ApiClient api;
  final String token;

  Future<void> _create(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _PayableDialog(api: api, token: token, suppliers: suppliers),
    );
    if (changed == true) await onChanged();
  }

  Future<void> _pay(BuildContext context, Payable payable) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _PayablePaymentDialog(api: api, token: token, payable: payable),
    );
    if (changed == true) await onChanged();
  }

  Future<void> _delete(BuildContext context, Payable payable) async {
    final title = payable.number ?? 'CP${payable.id}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta a pagar?'),
        content: Text(
          'Deseja realmente excluir "$title - ${payable.description}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deletePayable(token, payable.id);
      await onChanged();
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final openBalance = payables.fold<double>(
      0,
      (sum, item) => sum + item.balanceAmount,
    );
    final overdue = payables.where((item) {
      final due = item.dueDate;
      return item.balanceAmount > 0.009 &&
          due != null &&
          due.isBefore(DateTime.now());
    }).length;
    return Column(
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Saldo a pagar: ${_money(openBalance)} | vencidos: $overdue',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova conta'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: payables.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma conta a pagar encontrada.'),
                )
              : ResponsiveDataTable(
                  child: DataTable(
                    columnSpacing: 28,
                    horizontalMargin: 18,
                    columns: const [
                      DataColumn(label: Text('Título')),
                      DataColumn(label: Text('Fornecedor')),
                      DataColumn(label: Text('Vencimento')),
                      DataColumn(label: Text('Original')),
                      DataColumn(label: Text('Pago')),
                      DataColumn(label: Text('Saldo')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Ações')),
                    ],
                    rows: [
                      for (final payable in payables)
                        DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  '${payable.number ?? 'CP${payable.id}'} - ${payable.description}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(payable.supplierName ?? '-')),
                            DataCell(Text(_date(payable.dueDate))),
                            DataCell(Text(_money(payable.originalAmount))),
                            DataCell(Text(_money(payable.paidAmount))),
                            DataCell(
                              Text(
                                _money(payable.balanceAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            DataCell(Text(_statusLabel(payable.status))),
                            DataCell(
                              SizedBox(
                                width: 166,
                                child: canManage
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (payable.balanceAmount > 0.009)
                                            SizedBox(
                                              height: 38,
                                              child: FilledButton.icon(
                                                onPressed: () =>
                                                    _pay(context, payable),
                                                icon: const Icon(
                                                  Icons.payments_outlined,
                                                ),
                                                label: const Text('Baixar'),
                                              ),
                                            )
                                          else
                                            const SizedBox(width: 100),
                                          IconButton(
                                            tooltip: payable.paidAmount > 0
                                                ? 'Conta com baixa não pode ser excluída'
                                                : 'Excluir conta',
                                            onPressed: payable.paidAmount > 0
                                                ? null
                                                : () =>
                                                      _delete(context, payable),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text('-'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _PayableDialog extends StatefulWidget {
  const _PayableDialog({
    required this.api,
    required this.token,
    required this.suppliers,
  });

  final ApiClient api;
  final String token;
  final List<Supplier> suppliers;

  @override
  State<_PayableDialog> createState() => _PayableDialogState();
}

class _PayableDialogState extends State<_PayableDialog> {
  final _description = TextEditingController();
  final _document = TextEditingController();
  final _category = TextEditingController();
  final _amount = TextEditingController(text: '0,00');
  final _dueDate = TextEditingController();
  final _notes = TextEditingController();
  int? _supplierId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _document.dispose();
    _category.dispose();
    _amount.dispose();
    _dueDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String value) {
    final parts = value.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  Future<void> _save() async {
    final amount = parseBrazilianNumber(_amount.text);
    if (_description.text.trim().length < 2) {
      setState(() => _error = 'Informe a descricao da conta.');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = 'Informe o valor da conta.');
      return;
    }
    final dueDate = _dueDate.text.trim().isEmpty
        ? null
        : _parseDate(_dueDate.text);
    if (_dueDate.text.trim().isNotEmpty && dueDate == null) {
      setState(() => _error = 'Vencimento deve estar em DD/MM/AAAA.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.createPayable(
        widget.token,
        PayablePayload(
          supplierId: _supplierId,
          description: _description.text,
          documentNumber: _document.text,
          category: _category.text,
          originalAmount: amount,
          dueDate: dueDate,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível criar a conta a pagar.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova conta a pagar'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: _supplierId,
                decoration: const InputDecoration(
                  labelText: 'Fornecedor (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Despesa avulsa / sem fornecedor'),
                  ),
                  for (final supplier in widget.suppliers)
                    DropdownMenuItem<int?>(
                      value: supplier.id,
                      child: Text(supplier.name),
                    ),
                ],
                onChanged: (value) => setState(() => _supplierId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _document,
                      decoration: const InputDecoration(
                        labelText: 'Documento/NF',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _category,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.text,
                      inputFormatters: const [BrazilianMoneyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _dueDate,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianDateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Vencimento',
                        hintText: 'DD/MM/AAAA',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}

class _PayablePaymentDialog extends StatefulWidget {
  const _PayablePaymentDialog({
    required this.api,
    required this.token,
    required this.payable,
  });

  final ApiClient api;
  final String token;
  final Payable payable;

  @override
  State<_PayablePaymentDialog> createState() => _PayablePaymentDialogState();
}

class _PayablePaymentDialogState extends State<_PayablePaymentDialog> {
  late final _amount = TextEditingController(
    text: formatBrazilianMoneyInput(widget.payable.balanceAmount),
  );
  final _notes = TextEditingController();
  String _method = 'dinheiro';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseBrazilianNumber(_amount.text);
    final amountCents = _toMoneyCents(amount);
    final balanceCents = _toMoneyCents(widget.payable.balanceAmount);
    if (amountCents <= 0) {
      setState(() => _error = 'Informe o valor pago.');
      return;
    }
    if (amountCents > balanceCents) {
      setState(() => _error = 'Valor maior que o saldo em aberto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.payPayable(
        widget.token,
        widget.payable.id,
        PayablePaymentPayload(
          amount: amount,
          method: _method,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível registrar o pagamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseBrazilianNumber(_amount.text);
    final remaining = (widget.payable.balanceAmount - amount)
        .clamp(0, double.infinity)
        .toDouble();
    return AlertDialog(
      title: Text(
        'Baixar ${widget.payable.number ?? 'CP${widget.payable.id}'}',
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewLine(
              'Saldo em aberto',
              widget.payable.balanceAmount,
              strong: true,
            ),
            _ReviewLine('Saldo após baixa', remaining),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.text,
              inputFormatters: const [BrazilianMoneyInputFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor pago',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Forma de pagamento',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                DropdownMenuItem(value: 'pix', child: Text('Pix')),
                DropdownMenuItem(value: 'debito', child: Text('Débito')),
                DropdownMenuItem(value: 'credito', child: Text('Crédito')),
                DropdownMenuItem(
                  value: 'transferencia',
                  child: Text('Transferência'),
                ),
                DropdownMenuItem(value: 'boleto', child: Text('Boleto')),
              ],
              onChanged: (value) =>
                  setState(() => _method = value ?? 'dinheiro'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_saving ? 'Salvando...' : 'Confirmar baixa'),
        ),
      ],
    );
  }
}

class _ClientReceivables {
  const _ClientReceivables({
    required this.receivables,
    this.client,
    this.fallbackName,
  });

  final Client? client;
  final String? fallbackName;
  final List<Receivable> receivables;

  String get name => client?.name ?? fallbackName ?? 'Cliente sem cadastro';
  int get openCount =>
      receivables.where((item) => item.balanceAmount > 0.009).length;
  double get original =>
      receivables.fold(0, (sum, item) => sum + item.originalAmount);
  double get paid => receivables.fold(0, (sum, item) => sum + item.paidAmount);
  double get balance =>
      receivables.fold(0, (sum, item) => sum + item.balanceAmount);
}

class _Summary {
  const _Summary(this.label, this.value, this.icon, {this.money = false});
  final String label;
  final Object value;
  final IconData icon;
  final bool money;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(summary.icon, color: const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  summary.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                Text(
                  summary.money
                      ? _money(summary.value as double)
                      : '${summary.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _creditLabel(Client? client) {
  if (client == null) return '-';
  if (!client.allowCredit) return 'Bloqueado';
  return '${client.creditStatus} / ${_money(client.creditLimit)}';
}

String _receivableStatementTitle(Receivable receivable) {
  final number = receivable.number ?? 'CR${receivable.id}';
  final installment = _installmentInfo(receivable.description);
  if (receivable.saleNumber == null) {
    return '$number - ${receivable.description}';
  }
  if (installment == null) return '$number - Venda ${receivable.saleNumber}';
  return '$number - Venda ${receivable.saleNumber} - parcela ${installment.current}/${installment.total}';
}

String _receivableStatementSubtitle(Receivable receivable) {
  final parts = <String>[
    _dateTime(receivable.saleSoldAt ?? receivable.createdAt),
    _statusLabel(receivable.status),
  ];
  if (receivable.dueDate != null) {
    parts.add('vence em ${_date(receivable.dueDate)}');
  }
  final method = _methodFromReceivableDescription(receivable.description);
  if (method != null) parts.add(method);
  return parts.join(' | ');
}

String _receivableBalanceLabel(Receivable receivable) {
  final installment = _installmentInfo(receivable.description);
  final value = _money(receivable.balanceAmount);
  return installment == null ? value : 'Parcela $value';
}

_InstallmentInfo? _installmentInfo(String description) {
  final match = RegExp(
    r'parcela\s+(\d+)\s*/\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(description);
  if (match == null) return null;
  final current = int.tryParse(match.group(1) ?? '');
  final total = int.tryParse(match.group(2) ?? '');
  if (current == null || total == null) return null;
  return _InstallmentInfo(current: current, total: total);
}

String? _methodFromReceivableDescription(String description) {
  final normalized = _normalize(description);
  if (normalized.contains('boleto')) return 'Boleto';
  if (normalized.contains('crediario')) return 'Crediário';
  return null;
}

class _InstallmentInfo {
  const _InstallmentInfo({required this.current, required this.total});

  final int current;
  final int total;
}

String _statusLabel(String value) {
  return switch (value) {
    'open' => 'Aberto',
    'partial' => 'Parcial',
    'paid' => 'Pago',
    'canceled' => 'Cancelado',
    _ => value,
  };
}

String _paymentLabel(String value) {
  return switch (value) {
    'dinheiro' || 'Dinheiro' => 'Dinheiro',
    'pix' || 'Pix' => 'Pix',
    'cartao_credito' || 'credito' || 'Credito' => 'Cartão de crédito',
    'cartao_debito' || 'debito' || 'Debito' => 'Cartão de débito',
    'crediario' => 'Crediário',
    'transferencia' => 'Transferência',
    _ => value,
  };
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

int _toMoneyCents(double value) => (value * 100).round();

String _date(DateTime? value) {
  if (value == null) return '-';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'õ': 'o',
    'ô': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}

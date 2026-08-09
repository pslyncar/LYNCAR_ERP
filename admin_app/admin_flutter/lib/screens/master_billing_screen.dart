import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/company.dart';
import '../models/company_billing.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class MasterBillingScreen extends StatefulWidget {
  const MasterBillingScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterBillingScreen> createState() => _MasterBillingScreenState();
}

class _MasterBillingScreenState extends State<MasterBillingScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  List<CompanyBilling> _billings = [];
  List<Company> _companies = [];
  String _statusFilter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listMasterBillings(widget.session.token),
        _api.listCompanies(widget.session.token),
      ]);
      setState(() {
        _billings = results[0] as List<CompanyBilling>;
        _companies = results[1] as List<Company>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CompanyBilling> get _filtered {
    return _billings.where((billing) {
      return _statusFilter == 'all' || billing.status == _statusFilter;
    }).toList();
  }

  Future<void> _generateCurrent() async {
    try {
      await _api.generateCurrentMasterBillings(widget.session.token);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _pay(CompanyBilling billing) async {
    try {
      await _api.payMasterBilling(widget.session.token, billing.id);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _cancel(CompanyBilling billing) async {
    try {
      await _api.cancelMasterBilling(widget.session.token, billing.id);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _generatePix(CompanyBilling billing) async {
    try {
      final updated = await _api.generateMasterBillingPix(
        widget.session.token,
        billing.id,
      );
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _PixDialog(billing: updated),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _syncPayment(CompanyBilling billing) async {
    try {
      await _api.syncMasterBillingPayment(widget.session.token, billing.id);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _createManual() async {
    final input = await showDialog<CompanyBillingCreate>(
      context: context,
      builder: (context) => _BillingDialog(companies: _companies),
    );
    if (input == null) return;
    try {
      await _api.createMasterBilling(widget.session.token, input);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _editBilling(CompanyBilling billing) async {
    final input = await showDialog<CompanyBillingUpdate>(
      context: context,
      builder: (context) =>
          _BillingDialog(companies: _companies, billing: billing),
    );
    if (input == null) return;
    try {
      await _api.updateMasterBilling(widget.session.token, billing.id, input);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  String _money(double value) =>
      'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Color _statusColor(CompanyBilling billing) {
    if (billing.status == 'paid') return const Color(0xFFDCFCE7);
    if (billing.status == 'canceled') return const Color(0xFFE2E8F0);
    if (billing.isOverdue) return const Color(0xFFFEE2E2);
    return const Color(0xFFE0F2FE);
  }

  String _statusLabel(CompanyBilling billing) {
    if (billing.status == 'paid') return 'Pago';
    if (billing.status == 'canceled') return 'Cancelado';
    if (billing.isOverdue) return 'Atrasado';
    return 'Pendente';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cobranças',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Mensalidades do sistema, baixas e pendências.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _generateCurrent,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Gerar mês atual'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createManual,
                icon: const Icon(Icons.add),
                label: const Text('Nova cobrança'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          AppCard(
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'pending', child: Text('Pendentes')),
                DropdownMenuItem(value: 'paid', child: Text('Pagos')),
                DropdownMenuItem(value: 'canceled', child: Text('Cancelados')),
              ],
              onChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'all'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppCard(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ResponsiveDataTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Cliente')),
                          DataColumn(label: Text('Mês')),
                          DataColumn(label: Text('Vencimento')),
                          DataColumn(label: Text('Valor')),
                          DataColumn(label: Text('Pagamento')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Ações')),
                        ],
                        rows: [
                          for (final billing in _filtered)
                            DataRow(
                              cells: [
                                DataCell(Text(billing.companyName)),
                                DataCell(Text(billing.referenceMonth)),
                                DataCell(Text(_date(billing.dueDate))),
                                DataCell(Text(_money(billing.amount))),
                                DataCell(Text(billing.paymentMethod ?? '-')),
                                DataCell(
                                  Chip(
                                    label: Text(_statusLabel(billing)),
                                    backgroundColor: _statusColor(billing),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar cobranca',
                                        onPressed: billing.status == 'paid'
                                            ? null
                                            : () => _editBilling(billing),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: billing.pixQrCode == null
                                            ? 'Gerar Pix'
                                            : 'Ver Pix',
                                        onPressed:
                                            billing.status == 'paid' ||
                                                billing.status == 'canceled'
                                            ? null
                                            : () => billing.pixQrCode == null
                                                  ? _generatePix(billing)
                                                  : showDialog<void>(
                                                      context: context,
                                                      builder: (context) =>
                                                          _PixDialog(
                                                            billing: billing,
                                                          ),
                                                    ),
                                        icon: const Icon(Icons.qr_code_2),
                                      ),
                                      IconButton(
                                        tooltip: 'Sincronizar Mercado Pago',
                                        onPressed:
                                            billing.mercadoPagoPaymentId ==
                                                    null ||
                                                billing.status == 'paid' ||
                                                billing.status == 'canceled'
                                            ? null
                                            : () => _syncPayment(billing),
                                        icon: const Icon(Icons.sync),
                                      ),
                                      IconButton(
                                        tooltip: 'Dar baixa',
                                        onPressed:
                                            billing.status == 'paid' ||
                                                billing.status == 'canceled'
                                            ? null
                                            : () => _pay(billing),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Cancelar cobrança',
                                        onPressed:
                                            billing.status == 'paid' ||
                                                billing.status == 'canceled'
                                            ? null
                                            : () => _cancel(billing),
                                        icon: const Icon(Icons.cancel_outlined),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingDialog extends StatefulWidget {
  const _BillingDialog({required this.companies, this.billing});

  final List<Company> companies;
  final CompanyBilling? billing;

  @override
  State<_BillingDialog> createState() => _BillingDialogState();
}

class _BillingDialogState extends State<_BillingDialog> {
  int? _companyId;
  late final TextEditingController _reference;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late DateTime _dueDate;
  String? _paymentMethod;
  String _status = 'pending';
  bool _useProrata = false;

  bool get _isEditing => widget.billing != null;

  @override
  void initState() {
    super.initState();
    final billing = widget.billing;
    final now = DateTime.now();
    _companyId = billing?.companyId;
    _reference = TextEditingController(
      text:
          billing?.referenceMonth ??
          '${now.year}-${now.month.toString().padLeft(2, '0')}',
    );
    _amount = TextEditingController(
      text: billing == null
          ? ''
          : billing.amount.toStringAsFixed(2).replaceAll('.', ','),
    );
    _notes = TextEditingController(text: billing?.notes ?? '');
    _dueDate = billing?.dueDate ?? now;
    _paymentMethod = billing?.paymentMethod;
    _status = billing?.status ?? 'pending';
  }

  @override
  void dispose() {
    _reference.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _amountValue() {
    final text = _amount.text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(text) ?? 0;
  }

  String _formatMoney(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  double _selectedMonthlyPrice() {
    if (_companyId == null) return 0;
    for (final company in widget.companies) {
      if (company.id == _companyId) {
        final text = (company.monthlyPrice ?? '')
            .trim()
            .replaceAll('.', '')
            .replaceAll(',', '.');
        return double.tryParse(text) ?? 0;
      }
    }
    return 0;
  }

  int _daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

  int _prorataDays(DateTime today, DateTime dueDate) {
    final start = DateTime(today.year, today.month, today.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (!due.isAfter(start)) return 1;
    return due.difference(start).inDays;
  }

  void _applyProrata() {
    final monthly = _selectedMonthlyPrice();
    if (monthly <= 0) return;
    final today = DateTime.now();
    final days = _prorataDays(today, _dueDate);
    final baseDays = _daysInMonth(today);
    final prorated = monthly * days / baseDays;
    setState(() {
      _useProrata = true;
      _amount.text = _formatMoney(prorated);
      final note =
          'Pro-rata calculado em ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}: $days/$baseDays dias sobre mensalidade de R\$ ${_formatMoney(monthly)}.';
      _notes.text = _notes.text.trim().isEmpty
          ? note
          : '${_notes.text.trim()}\n$note';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar cobranca' : 'Nova cobranca'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  for (final company in widget.companies)
                    DropdownMenuItem(
                      value: company.id,
                      child: Text(company.name),
                    ),
                ],
                onChanged: _isEditing
                    ? null
                    : (value) {
                        Company? selected;
                        for (final company in widget.companies) {
                          if (company.id == value) selected = company;
                        }
                        setState(() {
                          _companyId = value;
                          _amount.text = selected?.monthlyPrice ?? '';
                        });
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reference,
                      enabled: !_isEditing,
                      decoration: const InputDecoration(labelText: 'Mes ref.'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      decoration: const InputDecoration(labelText: 'Valor'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        'Vencimento ${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _companyId == null ? null : _applyProrata,
                    icon: const Icon(Icons.percent),
                    label: const Text('Calcular pro-rata'),
                  ),
                ],
              ),
              if (_useProrata) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pro-rata: dias ate o vencimento / dias do mes atual x mensalidade.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(labelText: 'Pagamento'),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Nao informado'),
                        ),
                        DropdownMenuItem(value: 'pix', child: Text('Pix')),
                        DropdownMenuItem(
                          value: 'boleto',
                          child: Text('Boleto'),
                        ),
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('Dinheiro'),
                        ),
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Manual'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _paymentMethod = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pendente'),
                        ),
                        DropdownMenuItem(
                          value: 'canceled',
                          child: Text('Cancelada'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? 'pending'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observacoes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _companyId == null || _amountValue() <= 0
              ? null
              : () {
                  final notes = _notes.text.trim().isEmpty
                      ? null
                      : _notes.text.trim();
                  if (_isEditing) {
                    Navigator.of(context).pop(
                      CompanyBillingUpdate(
                        dueDate: _dueDate,
                        amount: _amountValue(),
                        paymentMethod: _paymentMethod,
                        status: _status,
                        notes: notes,
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop(
                    CompanyBillingCreate(
                      companyId: _companyId!,
                      referenceMonth: _reference.text.trim(),
                      dueDate: _dueDate,
                      amount: _amountValue(),
                      paymentMethod: _paymentMethod,
                      notes: notes,
                    ),
                  );
                },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _PixDialog extends StatelessWidget {
  const _PixDialog({required this.billing});

  final CompanyBilling billing;

  @override
  Widget build(BuildContext context) {
    final qrBase64 = billing.pixQrCodeBase64;
    final qrBytes = qrBase64 == null || qrBase64.isEmpty
        ? null
        : base64Decode(qrBase64);

    return AlertDialog(
      title: const Text('Pix da cobrança'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${billing.companyName} - ${billing.referenceMonth}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Status Mercado Pago: ${billing.mercadoPagoStatus ?? '-'}'),
            if (billing.mercadoPagoPaymentId != null)
              Text('Pagamento: ${billing.mercadoPagoPaymentId}'),
            const SizedBox(height: 14),
            if (qrBytes != null)
              Center(
                child: Image.memory(
                  qrBytes,
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                ),
              ),
            if ((billing.pixQrCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Pix copia e cola',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SelectableText(billing.pixQrCode!, maxLines: 5),
            ],
            if ((billing.pixTicketUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText('Link: ${billing.pixTicketUrl!}'),
            ],
          ],
        ),
      ),
      actions: [
        if ((billing.pixQrCode ?? '').isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: billing.pixQrCode!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código Pix copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar Pix'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

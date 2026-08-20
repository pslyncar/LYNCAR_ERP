import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/fiscal.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import '../services/fiscal_print.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class FiscalDocumentsScreen extends StatefulWidget {
  const FiscalDocumentsScreen({
    super.key,
    required this.session,
    required this.onStartIssue,
  });

  final Session session;
  final VoidCallback onStartIssue;

  @override
  State<FiscalDocumentsScreen> createState() => _FiscalDocumentsScreenState();
}

class _FiscalDocumentsScreenState extends State<FiscalDocumentsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  CompanyFiscalSetting? _settings;
  List<FiscalDocument> _documents = [];
  bool _loading = true;
  String? _error;
  int? _authorizingId;
  int? _downloadingXmlId;
  bool _autoSyncingContingency = false;
  Timer? _contingencySyncTimer;
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  final _search = TextEditingController();

  bool get _canEmit => widget.session.can('fiscal:emit');
  bool get _canCancel => widget.session.can('fiscal:cancel');

  @override
  void initState() {
    super.initState();
    _load();
    _contingencySyncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_loading && mounted) {
        unawaited(_syncContingenciesFromCurrentList());
      }
    });
  }

  @override
  void dispose() {
    _contingencySyncTimer?.cancel();
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
        _api.getFiscalSettings(widget.session.token),
        _api.listFiscalDocuments(widget.session.token, limit: 200),
      ]);
      final syncedDocuments = await _autoTransmitContingencies(
        results[1] as List<FiscalDocument>,
      );
      if (!mounted) return;
      setState(() {
        _settings = results[0] as CompanyFiscalSetting;
        _documents = syncedDocuments;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível interpretar os dados fiscais recebidos: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncContingenciesFromCurrentList() async {
    final syncedDocuments = await _autoTransmitContingencies(_documents);
    if (!mounted) return;
    setState(() => _documents = syncedDocuments);
  }

  Future<List<FiscalDocument>> _autoTransmitContingencies(
    List<FiscalDocument> documents,
  ) async {
    if (_autoSyncingContingency || !_canEmit) return documents;
    final pending = documents
        .where(
          (document) =>
              document.documentType.toLowerCase() == 'nfce' &&
              document.status == 'contingency_offline',
        )
        .toList();
    if (pending.isEmpty) return documents;

    _autoSyncingContingency = true;
    var syncedDocuments = [...documents];
    var transmitted = 0;
    try {
      for (final document in pending) {
        try {
          final updated = await _api.transmitFiscalContingencyDocument(
            widget.session.token,
            document.id,
          );
          transmitted++;
          syncedDocuments = [
            for (final item in syncedDocuments)
              if (item.id == updated.id) updated else item,
          ];
        } catch (_) {
          // SEFAZ/API ainda indisponivel: mantem em contingencia para nova tentativa.
        }
      }
    } finally {
      _autoSyncingContingency = false;
    }

    if (transmitted > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            transmitted == 1
                ? '1 NFC-e em contingencia foi transmitida automaticamente.'
                : '$transmitted NFC-e em contingencia foram transmitidas automaticamente.',
          ),
        ),
      );
    }
    return syncedDocuments;
  }

  List<FiscalDocument> get _filteredDocuments {
    final query = _search.text.trim().toLowerCase();
    return _documents.where((document) {
      if (_typeFilter != 'all' && document.documentType != _typeFilter) {
        return false;
      }
      if (_statusFilter != 'all' && document.status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        document.number?.toString(),
        document.series?.toString(),
        document.accessKey,
        document.consumerCpf,
        document.recipientDocument,
        document.recipientName,
        document.sefazMessage,
        document.saleId?.toString(),
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDocuments;
    final authorized = _documents
        .where((document) => document.status == 'authorized')
        .length;
    final pending = _documents
        .where(
          (document) =>
              document.status == 'draft' ||
              document.status == 'pending_certificate' ||
              document.status == 'xml_generated' ||
              document.status == 'signed' ||
              document.status == 'sent' ||
              document.status == 'contingency_offline',
        )
        .length;
    final rejected = _documents
        .where((document) => document.status == 'rejected')
        .length;
    final cancelled = _documents
        .where((document) => document.status == 'cancelled')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notas fiscais',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Emissão, acompanhamento e histórico de NFC-e e NF-e',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _canEmit && !_loading ? widget.onStartIssue : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Emitir nota'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            if (_error != null) ...[
              ErrorPanel(message: _error!, onRetry: _load),
              const SizedBox(height: 14),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  label: 'Total',
                  value: '${_documents.length}',
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF2563EB),
                ),
                _SummaryCard(
                  label: 'Autorizadas',
                  value: '$authorized',
                  icon: Icons.verified_outlined,
                  color: const Color(0xFF059669),
                ),
                _SummaryCard(
                  label: 'Pendentes',
                  value: '$pending',
                  icon: Icons.schedule_outlined,
                  color: const Color(0xFFD97706),
                ),
                _SummaryCard(
                  label: 'Rejeitadas',
                  value: '$rejected',
                  icon: Icons.error_outline,
                  color: const Color(0xFFDC2626),
                ),
                _SummaryCard(
                  label: 'Canceladas',
                  value: '$cancelled',
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFF7F1D1D),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 340,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText:
                                'Pesquisar nota, venda, CPF/CNPJ ou chave',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          initialValue: _typeFilter,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'nfce',
                              child: Text('NFC-e'),
                            ),
                            DropdownMenuItem(value: 'nfe', child: Text('NF-e')),
                          ],
                          onChanged: (value) =>
                              setState(() => _typeFilter = value ?? 'all'),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'authorized',
                              child: Text('Autorizada'),
                            ),
                            DropdownMenuItem(
                              value: 'draft',
                              child: Text('Preparada'),
                            ),
                            DropdownMenuItem(
                              value: 'pending_certificate',
                              child: Text('Aguardando A1'),
                            ),
                            DropdownMenuItem(
                              value: 'rejected',
                              child: Text('Rejeitada'),
                            ),
                            DropdownMenuItem(
                              value: 'contingency_offline',
                              child: Text('Contingência'),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled',
                              child: Text('Cancelada'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _statusFilter = value ?? 'all'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'Nenhuma nota encontrada com estes filtros.',
                        ),
                      ),
                    )
                  else
                    ResponsiveDataTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Documento')),
                          DataColumn(label: Text('Venda')),
                          DataColumn(label: Text('Emissão')),
                          DataColumn(label: Text('Destinatário')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Ambiente')),
                          DataColumn(label: Text('Ações')),
                        ],
                        rows: [
                          for (final document in filtered)
                            DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        document.documentType == 'nfce'
                                            ? 'NFC-e'
                                            : 'NF-e',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        document.number == null
                                            ? 'Modelo ${document.model}'
                                            : '${document.series ?? 1}/${document.number}',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    document.saleId == null
                                        ? '-'
                                        : '#${document.saleId}',
                                  ),
                                ),
                                DataCell(Text(_formatDate(document.createdAt))),
                                DataCell(
                                  Text(
                                    document.recipientName ??
                                        document.recipientDocument ??
                                        document.consumerCpf ??
                                        'Consumidor não identificado',
                                  ),
                                ),
                                DataCell(_StatusChip(status: document.status)),
                                DataCell(
                                  Text(
                                    document.environment == 'producao'
                                        ? 'Produção'
                                        : 'Homologação',
                                  ),
                                ),
                                DataCell(
                                  PopupMenuButton<String>(
                                    tooltip: 'Ações',
                                    onSelected: (action) =>
                                        _handleAction(action, document),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'details',
                                        child: _ActionLine(
                                          icon: Icons.visibility_outlined,
                                          label: 'Ver detalhes',
                                        ),
                                      ),
                                      if (_canEmit &&
                                          document.status != 'authorized' &&
                                          document.status != 'cancelled' &&
                                          document.status !=
                                              'contingency_offline')
                                        const PopupMenuItem(
                                          value: 'review',
                                          child: _ActionLine(
                                            icon: Icons.edit_note_outlined,
                                            label: 'Revisar / editar rascunho',
                                          ),
                                        ),
                                      if (_canAuthorize(document))
                                        PopupMenuItem(
                                          value: 'authorize',
                                          enabled:
                                              _authorizingId != document.id,
                                          child: const _ActionLine(
                                            icon: Icons.cloud_upload_outlined,
                                            label: 'Enviar para SEFAZ',
                                          ),
                                        ),
                                      if (document.status ==
                                              'contingency_offline' &&
                                          _canEmit)
                                        PopupMenuItem(
                                          value: 'transmit_contingency',
                                          enabled:
                                              _authorizingId != document.id,
                                          child: const _ActionLine(
                                            icon: Icons.cloud_sync_outlined,
                                            label: 'Transmitir contingência',
                                          ),
                                        ),
                                      if (document.status == 'authorized' ||
                                          document.status == 'cancelled' ||
                                          document.status ==
                                              'contingency_offline')
                                        const PopupMenuItem(
                                          value: 'print',
                                          child: _ActionLine(
                                            icon: Icons.print_outlined,
                                            label: 'Imprimir',
                                          ),
                                        ),
                                      if (document.status == 'authorized' ||
                                          document.status == 'cancelled')
                                        PopupMenuItem(
                                          value: 'download_xml',
                                          enabled:
                                              _downloadingXmlId != document.id,
                                          child: const _ActionLine(
                                            icon: Icons.download_outlined,
                                            label: 'Baixar XML',
                                          ),
                                        ),
                                      if (document.status == 'authorized' &&
                                          _canCancel)
                                        const PopupMenuItem(
                                          value: 'cancel',
                                          child: _ActionLine(
                                            icon: Icons.cancel_outlined,
                                            label: 'Cancelar nota',
                                            danger: true,
                                          ),
                                        ),
                                    ],
                                    child: _authorizingId == document.id
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.more_vert),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAuthorize(FiscalDocument document) {
    return _canEmit &&
        document.status != 'authorized' &&
        document.status != 'cancelled' &&
        document.status != 'contingency_offline';
  }

  // Transitional implementation retained only while its product/client selectors
  // are extracted into EmitirNotaFiscalScreen.
  // ignore: unused_element
  Future<void> _openIssueDialog() async {
    final settings = _settings;
    if (settings == null) return;
    var step = 0;
    var type = 'nfce';
    var paymentCondition = 'vista';
    var operationNature = _fiscalOperationOptions.first.value;
    final saleNumber = TextEditingController();
    final cpf = TextEditingController();
    final fiscalNotes = TextEditingController();
    FiscalSaleDraft? draft;
    Client? fiscalClient;
    var draftItems = <FiscalDraftItem>[];
    var loadingSale = false;
    var manualMode = false;
    String? dialogError;

    double fiscalTotal() => draftItems
        .where((item) => item.included)
        .fold(0, (sum, item) => sum + item.totalPrice);

    String itemCode(FiscalDraftItem item) {
      final barcode = item.barcode?.trim();
      if (barcode != null && barcode.isNotEmpty) return barcode;
      return 'Sem GTIN';
    }

    String clientLabel(Client? client) {
      if (client == null) {
        return manualMode
            ? 'Consumidor nao identificado / selecione cliente se precisar'
            : 'Cliente da venda / consumidor da venda';
      }
      final document = client.documentNumber?.trim();
      return [
        client.name,
        if (document != null && document.isNotEmpty) document,
        if (client.city?.trim().isNotEmpty == true ||
            client.state?.trim().isNotEmpty == true)
          '${client.city ?? '-'} / ${client.state ?? '-'}',
      ].join(' • ');
    }

    try {
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final nfeSelected = type == 'nfe';
              final typeEnabled = nfeSelected
                  ? settings.nfeEnabled
                  : settings.nfceEnabled;
              final visibleItems = draftItems
                  .asMap()
                  .entries
                  .where((entry) => entry.value.included)
                  .toList();

              Future<void> loadSale() async {
                final number = saleNumber.text.trim();
                if (number.isEmpty) {
                  setDialogState(
                    () => dialogError = 'Digite o numero da venda.',
                  );
                  return;
                }
                setDialogState(() {
                  loadingSale = true;
                  dialogError = null;
                });
                try {
                  final loaded = await _api.getFiscalSaleDraft(
                    widget.session.token,
                    number,
                  );
                  setDialogState(() {
                    draft = loaded;
                    draftItems = [...loaded.items];
                    manualMode = false;
                    fiscalClient = null;
                    cpf.text = loaded.consumerCpf ?? '';
                    step = 1;
                    loadingSale = false;
                  });
                } on ApiException catch (error) {
                  setDialogState(() {
                    dialogError = error.message;
                    loadingSale = false;
                  });
                } catch (_) {
                  setDialogState(() {
                    dialogError = 'Nao foi possivel carregar a venda.';
                    loadingSale = false;
                  });
                }
              }

              Future<void> replaceProduct(int index) async {
                final selected = await _selectFiscalProduct(dialogContext);
                if (selected == null) return;
                final current = draftItems[index];
                final total =
                    current.quantity * current.unitPrice -
                    current.discountAmount;
                setDialogState(() {
                  draftItems[index] = current.copyWith(
                    fiscalProductId: selected.id,
                    fiscalProductName: selected.name,
                    fiscalDescription: selected.name,
                    barcode: selected.barcode,
                    unit: selected.unit,
                    totalPrice: total < 0 ? 0 : total,
                    adjustmentReason:
                        'Produto fiscal substituido por ${selected.name}.',
                  );
                });
              }

              Future<void> addProduct() async {
                final selected = await _selectFiscalProduct(dialogContext);
                if (selected == null) return;
                final price = selected.salePrice;
                setDialogState(() {
                  draftItems.add(
                    FiscalDraftItem(
                      saleItemId: null,
                      originalProductId: null,
                      originalProductName: null,
                      fiscalProductId: selected.id,
                      fiscalProductName: selected.name,
                      originalDescription: null,
                      fiscalDescription: selected.name,
                      quantity: 1,
                      unit: selected.unit,
                      unitPrice: price,
                      discountAmount: 0,
                      totalPrice: price,
                      barcode: selected.barcode,
                      included: true,
                      adjustmentReason:
                          'Produto adicionado manualmente na pre-nota fiscal.',
                    ),
                  );
                });
              }

              Future<void> editValue(int index) async {
                final current = draftItems[index];
                final controller = TextEditingController(
                  text: current.unitPrice
                      .toStringAsFixed(2)
                      .replaceAll('.', ','),
                );
                final result = await showDialog<double>(
                  context: dialogContext,
                  builder: (context) => AlertDialog(
                    title: const Text('Alterar valor fiscal do item'),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valor unitario na nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final value =
                              double.tryParse(
                                controller.text
                                    .trim()
                                    .replaceAll('.', '')
                                    .replaceAll(',', '.'),
                              ) ??
                              current.unitPrice;
                          Navigator.of(context).pop(value);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (result == null) return;
                final total =
                    current.quantity * result - current.discountAmount;
                setDialogState(() {
                  draftItems[index] = current.copyWith(
                    unitPrice: result,
                    totalPrice: total < 0 ? 0 : total,
                    adjustmentReason:
                        'Valor fiscal do item alterado manualmente.',
                  );
                });
              }

              Future<void> editQuantity(int index) async {
                final current = draftItems[index];
                final controller = TextEditingController(
                  text: current.quantity
                      .toStringAsFixed(3)
                      .replaceAll('.', ','),
                );
                final result = await showDialog<double>(
                  context: dialogContext,
                  builder: (context) => AlertDialog(
                    title: const Text('Alterar quantidade fiscal'),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantidade na nota (${current.unit})',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final value =
                              double.tryParse(
                                controller.text
                                    .trim()
                                    .replaceAll('.', '')
                                    .replaceAll(',', '.'),
                              ) ??
                              current.quantity;
                          if (value <= 0) return;
                          Navigator.of(context).pop(value);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (result == null) return;
                final total =
                    result * current.unitPrice - current.discountAmount;
                setDialogState(() {
                  draftItems[index] = current.copyWith(
                    quantity: result,
                    totalPrice: total < 0 ? 0 : total,
                    adjustmentReason:
                        'Quantidade fiscal do item alterada manualmente.',
                  );
                });
              }

              Future<void> editDescription(int index) async {
                final current = draftItems[index];
                final controller = TextEditingController(
                  text: current.fiscalDescription,
                );
                final result = await showDialog<String>(
                  context: dialogContext,
                  builder: (context) => AlertDialog(
                    title: const Text('Editar descricao fiscal'),
                    content: TextField(
                      controller: controller,
                      maxLength: 220,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Descricao que saira na nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final value = controller.text.trim();
                          if (value.isEmpty) return;
                          Navigator.of(context).pop(value);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (result == null) return;
                setDialogState(() {
                  draftItems[index] = current.copyWith(
                    fiscalDescription: result,
                    adjustmentReason: 'Descricao fiscal alterada manualmente.',
                  );
                });
              }

              void deleteItem(int index) {
                final current = draftItems[index];
                setDialogState(() {
                  draftItems[index] = current.copyWith(
                    included: false,
                    adjustmentReason: 'Item excluido da emissao fiscal.',
                  );
                });
              }

              Future<void> chooseFiscalClient() async {
                final selected = await _selectFiscalClient(dialogContext);
                if (selected == null) return;
                setDialogState(() {
                  fiscalClient = selected;
                  if (!nfeSelected) {
                    cpf.text = selected.documentNumber ?? cpf.text;
                  }
                });
              }

              final title = step == 0
                  ? 'Pesquisar venda para emitir nota'
                  : manualMode
                  ? 'Montar nota fiscal manual'
                  : 'Montar nota fiscal da venda ${draft?.saleNumber ?? '#${draft?.saleId ?? '-'}'}';

              return Scaffold(
                appBar: AppBar(
                  title: Text(title),
                  leading: IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        child: step == 0
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Informe uma venda para emitir a partir dela ou crie uma nota manual escolhendo cliente, produtos, valores e observacoes.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: saleNumber,
                                          autofocus: true,
                                          onSubmitted: (_) => loadSale(),
                                          decoration: const InputDecoration(
                                            labelText: 'Numero da venda',
                                            hintText: 'Ex.: V45, 45 ou V87',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      FilledButton.icon(
                                        onPressed: loadingSale
                                            ? null
                                            : loadSale,
                                        icon: loadingSale
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.search),
                                        label: const Text('Buscar venda'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => setDialogState(() {
                                      manualMode = true;
                                      draft = null;
                                      draftItems = [];
                                      fiscalClient = null;
                                      cpf.clear();
                                      dialogError = null;
                                      step = 1;
                                    }),
                                    icon: const Icon(Icons.edit_note_outlined),
                                    label: const Text('Criar nota manual'),
                                  ),
                                  if (dialogError != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      dialogError!,
                                      style: const TextStyle(
                                        color: Color(0xFFB91C1C),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFBFDBFE),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            manualMode
                                                ? 'Nota manual | Total da nota ${_formatMoney(fiscalTotal())}'
                                                : 'Venda original ${_formatMoney(draft!.saleTotal)} | Total da nota ${_formatMoney(fiscalTotal())}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          manualMode
                                              ? 'Ao autorizar, o estoque sera baixado pelos itens desta nota.'
                                              : 'A venda original nao sera alterada.',
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'nfce',
                                        icon: Icon(
                                          Icons.point_of_sale_outlined,
                                        ),
                                        label: Text('NFC-e'),
                                      ),
                                      ButtonSegment(
                                        value: 'nfe',
                                        icon: Icon(
                                          Icons.local_shipping_outlined,
                                        ),
                                        label: Text('NF-e'),
                                      ),
                                    ],
                                    selected: {type},
                                    onSelectionChanged: (value) =>
                                        setDialogState(
                                          () => type = value.first,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (nfeSelected && !settings.nfeEnabled)
                                    const _PendingEngineBox(
                                      text:
                                          'A NF-e esta desabilitada. Ative e complete os dados fiscais em Configuracoes > Fiscal.',
                                    )
                                  else if (!nfeSelected &&
                                      !settings.nfceEnabled)
                                    const _PendingEngineBox(
                                      text:
                                          'A NFC-e esta desabilitada. Ative e configure o modulo em Configuracoes > Fiscal.',
                                    ),
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFD7E2F0),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.person_search_outlined,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Cliente/destinatario fiscal',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                clientLabel(fiscalClient),
                                                style: const TextStyle(
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                'Trocar aqui altera somente a nota fiscal. A venda/notinha original nao muda.',
                                                style: TextStyle(
                                                  color: Color(0xFF64748B),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: chooseFiscalClient,
                                              icon: const Icon(Icons.search),
                                              label: const Text(
                                                'Trocar cliente',
                                              ),
                                            ),
                                            if (fiscalClient != null)
                                              TextButton(
                                                onPressed: () => setDialogState(
                                                  () => fiscalClient = null,
                                                ),
                                                child: Text(
                                                  manualMode
                                                      ? 'Remover cliente'
                                                      : 'Usar da venda',
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Produtos da nota',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: addProduct,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Adicionar produto'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (visibleItems.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xFFD7E2F0),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Nenhum produto incluido na nota.',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    )
                                  else
                                    for (final entry in visibleItems)
                                      _FiscalDraftItemCard(
                                        item: entry.value,
                                        code: itemCode(entry.value),
                                        onReplaceProduct: () =>
                                            replaceProduct(entry.key),
                                        onEditValue: () => editValue(entry.key),
                                        onEditQuantity: () =>
                                            editQuantity(entry.key),
                                        onEditDescription: () =>
                                            editDescription(entry.key),
                                        onDelete: () => deleteItem(entry.key),
                                      ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    initialValue: operationNature,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Natureza da operacao',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final option
                                          in _fiscalOperationOptions)
                                        DropdownMenuItem(
                                          value: option.value,
                                          child: Text(
                                            option.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) => setDialogState(
                                      () => operationNature =
                                          value ??
                                          _fiscalOperationOptions.first.value,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    initialValue: paymentCondition,
                                    decoration: const InputDecoration(
                                      labelText: 'Condicao de pagamento fiscal',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'vista',
                                        child: Text('Pagamento a vista'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'prazo',
                                        child: Text('Pagamento a prazo'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'outros',
                                        child: Text('Outros'),
                                      ),
                                    ],
                                    onChanged: (value) => setDialogState(
                                      () => paymentCondition = value ?? 'vista',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (!nfeSelected)
                                    TextField(
                                      controller: cpf,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'CPF do consumidor (opcional para NFC-e)',
                                        border: OutlineInputBorder(),
                                      ),
                                    )
                                  else
                                    const Text(
                                      'A NF-e usara o cliente/destinatario fiscal selecionado acima. O cadastro precisa ter CPF/CNPJ, endereco completo, cidade, UF e CEP.',
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: fiscalNotes,
                                    minLines: 2,
                                    maxLines: 4,
                                    maxLength: 2000,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Observacoes fiscais complementares',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                bottomNavigationBar: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            if (step == 1) {
                              setDialogState(() => step = 0);
                            } else {
                              Navigator.of(dialogContext).pop(false);
                            }
                          },
                          child: Text(step == 1 ? 'Voltar' : 'Cancelar'),
                        ),
                        if (step == 1) ...[
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed:
                                !typeEnabled ||
                                    !draftItems.any((item) => item.included)
                                ? null
                                : () => Navigator.of(dialogContext).pop(true),
                            icon: const Icon(Icons.description_outlined),
                            label: Text(
                              nfeSelected ? 'Preparar NF-e' : 'Preparar NFC-e',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (confirmed != true) return;
      final document = manualMode
          ? await _api.prepareManualFiscalDocument(
              widget.session.token,
              items: draftItems,
              documentType: type,
              fiscalClientId: fiscalClient?.id,
              consumerCpf: type == 'nfce' && cpf.text.trim().isNotEmpty
                  ? cpf.text.trim()
                  : null,
              operationNature: operationNature,
              paymentCondition: paymentCondition,
              fiscalNotes: fiscalNotes.text.trim().isEmpty
                  ? null
                  : fiscalNotes.text.trim(),
            )
          : await _api.prepareFiscalDocumentWithItems(
              widget.session.token,
              saleId: draft!.saleId,
              items: draftItems,
              documentType: type,
              fiscalClientId: fiscalClient?.id,
              consumerCpf: type == 'nfce' && cpf.text.trim().isNotEmpty
                  ? cpf.text.trim()
                  : null,
              operationNature: operationNature,
              paymentCondition: paymentCondition,
              fiscalNotes: fiscalNotes.text.trim().isEmpty
                  ? null
                  : fiscalNotes.text.trim(),
            );
      if (!mounted) return;
      setState(() => _documents = [document, ..._documents]);
      await _reviewDocument(document);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            manualMode
                ? '${type == 'nfce' ? 'NFC-e' : 'NF-e'} manual preparada. Ao autorizar, o estoque sera baixado.'
                : '${type == 'nfce' ? 'NFC-e' : 'NF-e'} preparada sem alterar a venda original.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      saleNumber.dispose();
      cpf.dispose();
      fiscalNotes.dispose();
    }
  }

  Future<Client?> _selectFiscalClient(BuildContext dialogContext) async {
    final search = TextEditingController();
    var clients = <Client>[];
    var filtered = <Client>[];
    var loading = true;
    var loadedInitial = false;
    String? error;

    String normalize(String value) => value.toLowerCase().trim();

    void applyFilter(StateSetter setDialogState) {
      final query = normalize(search.text);
      setDialogState(() {
        filtered = clients.where((client) {
          if (query.isEmpty) return true;
          final haystack = normalize(
            [
              client.name,
              client.tradeName,
              client.documentNumber,
              client.phone,
              client.mobilePhone,
              client.email,
              client.city,
              client.state,
            ].whereType<String>().join(' '),
          );
          return haystack.contains(query);
        }).toList();
      });
    }

    try {
      return await showDialog<Client>(
        context: dialogContext,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> loadClients() async {
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final result = await _api.listClients(widget.session.token);
                setDialogState(() {
                  clients = result.where((client) => client.active).toList();
                  filtered = clients;
                  loading = false;
                });
              } on ApiException catch (apiError) {
                setDialogState(() {
                  error = apiError.message;
                  loading = false;
                });
              } catch (_) {
                setDialogState(() {
                  error = 'Nao foi possivel carregar clientes.';
                  loading = false;
                });
              }
            }

            if (!loadedInitial) {
              loadedInitial = true;
              Future.microtask(loadClients);
            }

            return AlertDialog(
              title: const Text('Escolher cliente fiscal'),
              content: SizedBox(
                width: 820,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      onChanged: (_) => applyFilter(setDialogState),
                      decoration: const InputDecoration(
                        labelText:
                            'Buscar por nome, CPF/CNPJ, telefone, e-mail ou cidade',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      )
                    else if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum cliente encontrado.'),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 430),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final client = filtered[index];
                            final document = client.documentNumber ?? '-';
                            final cityState = [
                              client.city,
                              client.state,
                            ].whereType<String>().join(' / ');
                            return ListTile(
                              leading: Icon(
                                client.personType == 'PJ'
                                    ? Icons.apartment_outlined
                                    : Icons.person_outline,
                              ),
                              title: Text(
                                client.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  document,
                                  if (cityState.trim().isNotEmpty) cityState,
                                  if (client.email?.trim().isNotEmpty == true)
                                    client.email!,
                                ].join(' • '),
                              ),
                              trailing: FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(client),
                                child: const Text('Usar'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      search.dispose();
    }
  }

  Future<FiscalProductLookup?> _selectFiscalProduct(
    BuildContext dialogContext,
  ) async {
    final search = TextEditingController();
    var products = <FiscalProductLookup>[];
    var loading = false;
    var loadedInitial = false;
    String? error;

    String productCode(FiscalProductLookup product) {
      final barcode = product.barcode?.trim();
      if (barcode != null && barcode.isNotEmpty) return barcode;
      return 'Sem GTIN';
    }

    try {
      return await showDialog<FiscalProductLookup>(
        context: dialogContext,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runSearch() async {
              final query = search.text.trim();
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final result = await _api.lookupFiscalProducts(
                  widget.session.token,
                  query,
                );
                setDialogState(() {
                  products = result;
                  loading = false;
                });
              } on ApiException catch (apiError) {
                setDialogState(() {
                  error = apiError.message;
                  loading = false;
                });
              } catch (_) {
                setDialogState(() {
                  error = 'Nao foi possivel buscar produtos.';
                  loading = false;
                });
              }
            }

            if (!loadedInitial) {
              loadedInitial = true;
              Future.microtask(runSearch);
            }

            return AlertDialog(
              title: const Text('Escolher produto do estoque'),
              content: SizedBox(
                width: 980,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: search,
                            onSubmitted: (_) => runSearch(),
                            decoration: const InputDecoration(
                              labelText:
                                  'Buscar por nome, codigo ou codigo de barras',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: loading ? null : runSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Buscar'),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (loading)
                      const LinearProgressIndicator()
                    else
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFD7E2F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              final code = productCode(product);
                              final hasFiscalStock =
                                  product.fiscalAvailableQuantity > 0;
                              return ListTile(
                                title: Text(
                                  '$code - ${product.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Wrap(
                                  spacing: 14,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Estoque ${product.stockQuantity.toStringAsFixed(2)} ${product.unit}',
                                    ),
                                    Text(
                                      'Valor ${_formatMoney(product.salePrice)}',
                                    ),
                                    Text(
                                      hasFiscalStock
                                          ? 'Com nota ${product.fiscalAvailableQuantity.toStringAsFixed(2)}'
                                          : 'Sem saldo de nota',
                                    ),
                                  ],
                                ),
                                trailing: FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(product),
                                  child: const Text('Usar'),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      search.dispose();
    }
  }

  Future<void> _handleAction(String action, FiscalDocument document) async {
    switch (action) {
      case 'details':
        await _showDetails(document);
      case 'review':
        await _reviewDocument(document);
      case 'authorize':
        await _authorize(document);
      case 'transmit_contingency':
        await _transmitContingency(document);
      case 'print':
        await _printDocument(document);
      case 'download_xml':
        await _downloadXml(document);
      case 'cancel':
        await _cancelDocument(document);
    }
  }

  Future<void> _authorize(FiscalDocument document) async {
    setState(() {
      _authorizingId = document.id;
      _error = null;
    });
    try {
      final updated = await _api.authorizeFiscalDocument(
        widget.session.token,
        document.id,
      );
      if (!mounted) return;
      setState(() {
        _documents = [
          for (final item in _documents)
            if (item.id == updated.id) updated else item,
        ];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _authorizingId = null);
    }
  }

  Future<void> _transmitContingency(FiscalDocument document) async {
    setState(() {
      _authorizingId = document.id;
      _error = null;
    });
    try {
      final updated = await _api.transmitFiscalContingencyDocument(
        widget.session.token,
        document.id,
      );
      if (!mounted) return;
      setState(() {
        _documents = [
          for (final item in _documents)
            if (item.id == updated.id) updated else item,
        ];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _authorizingId = null);
    }
  }

  Future<void> _printDocument(FiscalDocument document) async {
    setState(() => _error = null);
    try {
      final bytes = await _api.getFiscalDanfe(
        widget.session.token,
        document.id,
      );
      await printFiscalPdf(
        filename:
            'danfe-${document.documentType}-${document.number ?? document.id}.pdf',
        bytes: bytes,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível abrir o DANFE para impressão.',
        );
      }
    }
  }

  Future<void> _downloadXml(FiscalDocument document) async {
    setState(() {
      _downloadingXmlId = document.id;
      _error = null;
    });
    try {
      final bytes = await _api.getFiscalDocumentXml(
        widget.session.token,
        document.id,
      );
      final series = document.series ?? 1;
      final number = document.number ?? document.id;
      downloadBytesFile(
        filename: '${document.documentType}-serie-$series-numero-$number.xml',
        bytes: bytes,
        mimeType: 'application/xml;charset=utf-8',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download do XML iniciado.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível baixar o XML da nota.');
      }
    } finally {
      if (mounted) setState(() => _downloadingXmlId = null);
    }
  }

  Future<void> _cancelDocument(FiscalDocument document) async {
    final reason = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancelar nota na SEFAZ'),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esta ação transmite um evento assinado para a SEFAZ. A nota só será marcada como cancelada se o evento for aceito.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reason,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Justificativa (mínimo de 15 caracteres)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Transmitir cancelamento'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final normalized = reason.text.trim();
      if (normalized.length < 15) {
        setState(
          () => _error =
              'A justificativa de cancelamento precisa ter pelo menos 15 caracteres.',
        );
        return;
      }
      final updated = await _api.cancelFiscalDocument(
        widget.session.token,
        document.id,
        normalized,
      );
      if (!mounted) return;
      setState(() {
        _documents = [
          for (final item in _documents)
            if (item.id == updated.id) updated else item,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancelamento aceito pela SEFAZ.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      reason.dispose();
    }
  }

  Future<void> _showDetails(FiscalDocument document) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${document.documentType == 'nfce' ? 'NFC-e' : 'NF-e'} ${document.number ?? ''}',
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine(
                  label: 'Status',
                  value: _statusLabel(document.status),
                ),
                _DetailLine(label: 'Modelo', value: document.model),
                _DetailLine(
                  label: 'Série / número',
                  value:
                      '${document.series ?? '-'} / ${document.number ?? '-'}',
                ),
                _DetailLine(
                  label: 'Ambiente',
                  value: document.environment == 'producao'
                      ? 'Produção'
                      : 'Homologação',
                ),
                _DetailLine(
                  label: 'Venda',
                  value: document.saleId == null ? '-' : '#${document.saleId}',
                ),
                _DetailLine(
                  label: 'CPF/CNPJ',
                  value:
                      document.recipientDocument ?? document.consumerCpf ?? '-',
                ),
                _DetailLine(
                  label: 'Destinatário',
                  value: document.recipientName ?? '-',
                ),
                _DetailLine(
                  label: 'Natureza',
                  value: document.operationNature ?? '-',
                ),
                _DetailLine(
                  label: 'Pagamento',
                  value: _paymentConditionLabel(document.paymentCondition),
                ),
                if (document.fiscalNotes != null &&
                    document.fiscalNotes!.trim().isNotEmpty)
                  _DetailLine(
                    label: 'Observações fiscais',
                    value: document.fiscalNotes!,
                  ),
                _DetailLine(
                  label: 'Chave de acesso',
                  value: document.accessKey ?? '-',
                  selectable: true,
                ),
                _DetailLine(
                  label: 'Protocolo',
                  value: document.sefazProtocol ?? '-',
                  selectable: true,
                ),
                _DetailLine(
                  label: 'Retorno SEFAZ',
                  value:
                      [
                        if (document.sefazStatusCode != null)
                          document.sefazStatusCode,
                        if (document.sefazMessage != null)
                          document.sefazMessage,
                      ].whereType<String>().join(' · ').isEmpty
                      ? '-'
                      : [
                          if (document.sefazStatusCode != null)
                            document.sefazStatusCode,
                          if (document.sefazMessage != null)
                            document.sefazMessage,
                        ].whereType<String>().join(' · '),
                ),
                _DetailLine(
                  label: 'Criada em',
                  value: _formatDateTime(document.createdAt),
                ),
                if (document.authorizedAt != null)
                  _DetailLine(
                    label: 'Autorizada em',
                    value: _formatDateTime(document.authorizedAt!),
                  ),
                if (document.cancelledAt != null)
                  _DetailLine(
                    label: 'Cancelada em',
                    value: _formatDateTime(document.cancelledAt!),
                  ),
                if (document.cancellationProtocol != null)
                  _DetailLine(
                    label: 'Protocolo cancelamento',
                    value: document.cancellationProtocol!,
                    selectable: true,
                  ),
                if (document.cancellationReason != null)
                  _DetailLine(
                    label: 'Justificativa',
                    value: document.cancellationReason!,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewDocument(FiscalDocument document) async {
    final nature = TextEditingController(text: document.operationNature ?? '');
    final notes = TextEditingController(text: document.fiscalNotes ?? '');
    final itemControllers = [
      for (final item in document.fiscalItems)
        (
          ncm: TextEditingController(text: item.ncm ?? ''),
          cfop: TextEditingController(text: item.cfop ?? ''),
          origin: TextEditingController(text: item.origin ?? ''),
          csosn: TextEditingController(text: item.csosn ?? ''),
        ),
    ];
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Revisar ${document.documentType == 'nfe' ? 'NF-e' : 'NFC-e'} #${document.id}',
          ),
          content: SizedBox(
            width: 860,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rascunho: revise e salve antes de enviar à SEFAZ. Notas rejeitadas também podem ser corrigidas aqui.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nature,
                    decoration: const InputDecoration(
                      labelText: 'Natureza da operação',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observações fiscais',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (
                    var index = 0;
                    index < document.fiscalItems.length;
                    index++
                  ) ...[
                    Text(
                      document.fiscalItems[index].fiscalDescription,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: itemControllers[index].ncm,
                            decoration: const InputDecoration(
                              labelText: 'NCM',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: itemControllers[index].cfop,
                            decoration: const InputDecoration(
                              labelText: 'CFOP',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: itemControllers[index].origin,
                            decoration: const InputDecoration(
                              labelText: 'Origem',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: itemControllers[index].csosn,
                            decoration: const InputDecoration(
                              labelText: 'CSOSN',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Salvar rascunho'),
            ),
          ],
        ),
      );
      if (save != true) return;
      final items = [
        for (var index = 0; index < document.fiscalItems.length; index++)
          document.fiscalItems[index].copyWith(
            ncm: itemControllers[index].ncm.text.trim(),
            cfop: itemControllers[index].cfop.text.trim(),
            origin: itemControllers[index].origin.text.trim(),
            csosn: itemControllers[index].csosn.text.trim(),
          ),
      ];
      final updated = await _api.updateFiscalDocument(
        widget.session.token,
        document.id,
        operationNature: nature.text.trim(),
        fiscalNotes: notes.text.trim(),
        items: items,
      );
      if (!mounted) return;
      setState(
        () => _documents = [
          for (final item in _documents)
            if (item.id == updated.id) updated else item,
        ],
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rascunho fiscal salvo para revisão.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      nature.dispose();
      notes.dispose();
      for (final controllers in itemControllers) {
        controllers.ncm.dispose();
        controllers.cfop.dispose();
        controllers.origin.dispose();
        controllers.csosn.dispose();
      }
    }
  }
}

class _FiscalDraftItemCard extends StatelessWidget {
  const _FiscalDraftItemCard({
    required this.item,
    required this.code,
    required this.onReplaceProduct,
    required this.onEditValue,
    required this.onEditQuantity,
    required this.onEditDescription,
    required this.onDelete,
  });

  final FiscalDraftItem item;
  final String code;
  final VoidCallback onReplaceProduct;
  final VoidCallback onEditValue;
  final VoidCallback onEditQuantity;
  final VoidCallback onEditDescription;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7E2F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fiscalDescription,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Produto fiscal: ${item.fiscalProductName ?? item.fiscalDescription}',
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Original da venda: ${item.originalProductName ?? item.originalDescription ?? 'produto adicionado na nota'}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.quantity.toStringAsFixed(3)} ${item.unit} x ${_formatMoney(item.unitPrice)} = ${_formatMoney(item.totalPrice)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if ((item.adjustmentReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.adjustmentReason!,
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onReplaceProduct,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Substituir'),
              ),
              OutlinedButton.icon(
                onPressed: onEditDescription,
                icon: const Icon(Icons.edit_note_outlined, size: 18),
                label: const Text('Descricao'),
              ),
              OutlinedButton.icon(
                onPressed: onEditQuantity,
                icon: const Icon(Icons.pin_outlined, size: 18),
                label: const Text('Qtd.'),
              ),
              OutlinedButton.icon(
                onPressed: onEditValue,
                icon: const Icon(Icons.attach_money, size: 18),
                label: const Text('Valor'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Excluir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'authorized' => const Color(0xFF047857),
      'contingency_offline' => const Color(0xFFD97706),
      'rejected' || 'cancelled' => const Color(0xFFB91C1C),
      'draft' || 'pending_certificate' => const Color(0xFFB45309),
      _ => const Color(0xFF475569),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionLine extends StatelessWidget {
  const _ActionLine({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB91C1C) : null;
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _PendingEngineBox extends StatelessWidget {
  const _PendingEngineBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.engineering_outlined, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(value)
        : Text(value, textAlign: TextAlign.right);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

class _FiscalOperationOption {
  const _FiscalOperationOption(this.code, this.description);

  final String code;
  final String description;

  String get value => '$code - $description';
  String get label => '$code - $description';
}

const _fiscalOperationOptions = [
  _FiscalOperationOption('5102', 'VENDA DE MERCADORIA'),
  _FiscalOperationOption('6102', 'VENDA INTERESTADUAL DE MERCADORIA'),
  _FiscalOperationOption('5405', 'VENDA DE MERCADORIA ST'),
  _FiscalOperationOption('6404', 'VENDA INTERESTADUAL DE MERCADORIA ST'),
  _FiscalOperationOption('5910', 'REMESSA EM BONIFICACAO, DOACAO OU BRINDE'),
  _FiscalOperationOption(
    '6910',
    'REMESSA INTERESTADUAL EM BONIFICACAO, DOACAO OU BRINDE',
  ),
  _FiscalOperationOption('5411', 'DEVOLUCAO DE MERCADORIA ST'),
  _FiscalOperationOption('6411', 'DEVOLUCAO INTERESTADUAL DE MERCADORIA ST'),
  _FiscalOperationOption('5915', 'REMESSA DE MERCADORIA OU BEM PARA CONSERTO'),
  _FiscalOperationOption(
    '6915',
    'REMESSA INTERESTADUAL DE MERCADORIA OU BEM PARA CONSERTO',
  ),
  _FiscalOperationOption('5929', 'DOCUMENTO FISCAL DO VAREJO'),
  _FiscalOperationOption('6929', 'DOCUMENTO FISCAL INTERESTADUAL DO VAREJO'),
  _FiscalOperationOption('5949', 'OUTRAS SAIDAS'),
  _FiscalOperationOption('6949', 'OUTRAS SAIDAS INTERESTADUAIS'),
];

String _statusLabel(String status) => switch (status) {
  'draft' => 'Preparada',
  'pending_certificate' => 'Aguardando A1',
  'xml_generated' => 'XML gerado',
  'signed' => 'Assinada',
  'sent' => 'Enviada',
  'contingency_offline' => 'Contingência offline',
  'authorized' => 'Autorizada',
  'rejected' => 'Rejeitada',
  'cancelled' => 'Cancelada',
  _ => status,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_formatDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _formatMoney(double value) {
  return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

String _paymentConditionLabel(String? condition) {
  return switch (condition) {
    'prazo' => 'Pagamento a prazo',
    'outros' => 'Outros',
    'vista' || null || '' => 'Pagamento à vista',
    _ => condition,
  };
}

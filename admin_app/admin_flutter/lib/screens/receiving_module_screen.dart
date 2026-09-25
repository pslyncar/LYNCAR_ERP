import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/session.dart';
import '../models/product.dart';
import '../models/stock_entry.dart';
import '../models/supplier.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import 'manual_receiving_screen.dart';
import 'receiving_conference_screen.dart';
import 'xml_inbox_screen.dart';

/// New receiving workspace. The legacy editor remains available while each
/// operation is being migrated into its own flow.
class ReceivingModuleScreen extends StatefulWidget {
  const ReceivingModuleScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReceivingModuleScreen> createState() => _ReceivingModuleScreenState();
}

class _ReceivingModuleScreenState extends State<ReceivingModuleScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  int _page = 1;
  String? _status;
  String? _source;
  int? _supplierId;
  int? _periodDays;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = true;
  String? _error;
  int _total = 0;
  Map<String, dynamic> _summary = const {};
  List<StockEntry> _entries = const [];
  List<XmlInboxMessage> _xmlInbox = const [];
  final Set<int> _selected = <int>{};
  bool _exporting = false;

  bool get _canReverseEntries =>
      widget.session.role == 'admin' ||
      widget.session.can('stock:entries:reverse');

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

  bool get _hasListCriteria =>
      _search.text.trim().isNotEmpty ||
      _status != null ||
      _source != null ||
      _supplierId != null ||
      _periodDays != null ||
      _fromDate != null ||
      _toDate != null;

  /// XML aguardando importação não deve transformar a central em uma caixa de
  /// entrada. Ele é exibido somente quando o usuário consulta o número/chave
  /// da NF que deseja receber.
  bool get _isInvoiceLookup {
    final lookup = _search.text.trim();
    return lookup.isNotEmpty && RegExp(r'^\d+$').hasMatch(lookup);
  }

  List<XmlInboxMessage> _matchingPendingXml(List<XmlInboxMessage> messages) {
    if (!_isInvoiceLookup) return const [];
    final lookup = _search.text.trim();
    return messages
        .where(
          (message) =>
              (message.status == 'pending_receipt' ||
                  message.status == 'pending_supplier') &&
              (message.invoiceNumber == lookup ||
                  (message.invoiceKey?.contains(lookup) ?? false)),
        )
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_hasListCriteria) {
        final summary = await _api.stockReceiptsSummary(widget.session.token);
        if (!mounted) return;
        setState(() {
          _entries = const [];
          _total = 0;
          _summary = summary;
          _xmlInbox = const [];
          _loading = false;
        });
        return;
      }
      final results = await Future.wait([
        _api.listStockReceiptsPage(
          widget.session.token,
          page: _page,
          status: _status,
          search: _search.text,
          source: _source,
          supplierId: _supplierId,
          createdFrom: _fromDate,
          createdTo: _toDate,
        ),
        _api.stockReceiptsSummary(widget.session.token),
      ]);
      List<XmlInboxMessage> xmlInbox = const [];
      if (_isInvoiceLookup) {
        try {
          xmlInbox = await _api.listXmlInboxMessages(
            widget.session.token,
            limit: 100,
          );
        } on ApiException {
          // The operational list remains available even if email sync is offline.
        }
      }
      final pageData = results[0];
      if (!mounted) return;
      setState(() {
        final loadedEntries = (pageData['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StockEntry.fromJson)
            .toList();
        final cutoff = _periodDays == null
            ? null
            : DateTime.now().subtract(Duration(days: _periodDays!));
        _entries = cutoff == null
            ? loadedEntries
            : loadedEntries
                  .where(
                    (entry) =>
                        entry.createdAt == null ||
                        entry.createdAt!.isAfter(cutoff),
                  )
                  .toList();
        _total = (pageData['total'] as num?)?.toInt() ?? 0;
        _summary = results[1];
        _xmlInbox = _matchingPendingXml(xmlInbox);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar o recebimento.';
          _loading = false;
        });
      }
    }
  }

  void _openManualReceiving() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualReceivingScreen(session: widget.session),
      ),
    );
  }

  void _openXmlInbox() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XmlInboxScreen(session: widget.session),
      ),
    );
  }

  Future<void> _registerPendingSupplier(XmlInboxMessage message) async {
    final nameController = TextEditingController(
      text: message.supplierName ?? '',
    );
    final documentController = TextEditingController(
      text: message.supplierDocument ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cadastrar fornecedor do XML'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Confira os dados identificados no XML. O CNPJ será usado para liberar esta nota.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Razão social / nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: documentController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'CNPJ/CPF do XML',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.verified_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Cadastrar fornecedor'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final document = documentController.text.trim();
    nameController.dispose();
    documentController.dispose();
    if (confirmed != true || name.length < 2 || document.isEmpty) return;
    try {
      await _api.createSupplier(
        widget.session.token,
        SupplierPayload(name: name, documentNumber: document),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fornecedor cadastrado. A nota foi liberada para importação.',
          ),
        ),
      );
      _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _reprocess(StockEntry entry) async {
    try {
      await _api.reprocessStockEntryMatching(widget.session.token, entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conciliação reprocessada sem movimentar estoque.'),
          ),
        );
        _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _showAudit(StockEntry entry) async {
    try {
      final events = await _api.listStockEntryAudit(
        widget.session.token,
        entry.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Histórico da entrada #${entry.id}'),
          content: SizedBox(
            width: 640,
            child: events.isEmpty
                ? const Text('Nenhum evento registrado ainda.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final date = event['created_at']?.toString() ?? '';
                      final user = event['user_name']?.toString() ?? 'Sistema';
                      final reason = event['reason']?.toString();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(event['action']?.toString() ?? 'Evento'),
                        subtitle: Text(
                          '$user • $date${reason == null || reason.isEmpty ? '' : '\n$reason'}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _confirm(StockEntry entry) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recebimento?'),
        content: const Text(
          'Somente agora o sistema movimentará estoque e custo. Depois da confirmação, a entrada não será editada; somente estornada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _api.confirmOpenStockEntry(widget.session.token, entry.id);
      if (mounted) {
        Navigator.pop(context);
        _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _reverse(StockEntry entry) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estornar entrada'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo obrigatório',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length >= 5) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null) return;
    try {
      await _api.reverseStockEntry(widget.session.token, entry.id, value);
      if (mounted) {
        Navigator.pop(context);
        _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _matchProduct(StockEntry entry, StockEntryItem item) async {
    if (item.id == null) return;
    try {
      final products = (await _api.listProducts(widget.session.token))
          .where(
            (product) => product.active && product.productType != 'servico',
          )
          .take(100)
          .toList();
      if (!mounted) return;
      final selected = await showDialog<Product>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Vincular: ${item.description}'),
          children: products
              .map(
                (product) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, product),
                  child: Text(product.name),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null) return;
      await _api.matchStockEntryItem(
        widget.session.token,
        entry.id,
        item.id!,
        selected.id,
      );
      if (mounted) {
        Navigator.pop(context);
        _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _importXml(XmlInboxMessage message) async {
    try {
      final entry = await _api.createReceiptFromXmlInbox(
        widget.session.token,
        message.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML importado na entrada #${entry.id}.')),
      );
      setState(() {
        // Após a importação, deixe a entrada oficial visível imediatamente.
        _status = 'receiving';
        _page = 1;
      });
      _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _pickAndUploadXml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível ler o XML selecionado.'),
          ),
        );
      }
      return;
    }
    try {
      await _api.uploadXmlInboxFile(
        widget.session.token,
        fileName: file.name,
        xmlContent: utf8.decode(file.bytes!, allowMalformed: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'XML validado. Pesquise o número ou a chave da NF para importá-lo.',
          ),
        ),
      );
      _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  bool get _canExport =>
      !_loading && !_exporting && (_total > 0 || _xmlInbox.isNotEmpty);

  Future<void> _exportCurrentQuery() async {
    if (!_canExport) return;
    setState(() => _exporting = true);
    try {
      final entries = <StockEntry>[];
      var page = 1;
      var total = 0;
      do {
        final result = await _api.listStockReceiptsPage(
          widget.session.token,
          page: page,
          pageSize: 100,
          status: _status,
          search: _search.text,
          source: _source,
          supplierId: _supplierId,
          createdFrom: _fromDate,
          createdTo: _toDate,
        );
        total = (result['total'] as num?)?.toInt() ?? 0;
        entries.addAll(
          (result['items'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(StockEntry.fromJson),
        );
        page++;
      } while (entries.length < total);

      final cutoff = _periodDays == null
          ? null
          : DateTime.now().subtract(Duration(days: _periodDays!));
      final filteredEntries = cutoff == null
          ? entries
          : entries
                .where(
                  (entry) =>
                      entry.createdAt == null ||
                      entry.createdAt!.isAfter(cutoff),
                )
                .toList();
      final lines = <String>[
        '\uFEFFRelatório de recebimento de mercadorias',
        'Gerado em;${_date(DateTime.now())}',
        'Consulta;${_search.text.trim().isEmpty ? 'Filtros aplicados' : _search.text.trim()}',
        '',
        'NF;Fornecedor;Emissão;Valor;Itens;Origem;Status;Chave NF-e',
        for (final xml in _xmlInbox)
          [
            xml.invoiceNumber ?? '',
            xml.supplierName ?? '',
            _date(xml.receivedAt),
            '',
            '',
            'XML',
            xml.status == 'pending_supplier'
                ? 'Fornecedor pendente'
                : 'XML pendente',
            xml.invoiceKey ?? '',
          ].map(_csvCell).join(';'),
        for (final entry in filteredEntries)
          [
            entry.invoiceNumber ?? '',
            entry.supplierName ?? '',
            _date(entry.createdAt),
            _money(entry.totalAmount),
            '${entry.items.length}',
            _sourceLabel(entry.source),
            _statusLabel(entry.status),
            entry.invoiceKey ?? '',
          ].map(_csvCell).join(';'),
      ];
      downloadTextFile(
        filename: 'recebimento_${_fileDate(DateTime.now())}.csv',
        content: lines.join('\r\n'),
        mimeType: 'text/csv;charset=utf-8',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_xmlInbox.length + filteredEntries.length} documento(s) exportado(s).',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  String _fileDate(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';

  String _statusLabel(String? status) {
    switch (status) {
      case 'draft':
        return 'Rascunho';
      case 'receiving':
        return 'Em conferência';
      case 'confirmed':
        return 'Finalizadas';
      case 'divergence':
        return 'Divergências';
      default:
        return 'A receber';
    }
  }

  ({String label, IconData icon, Color color}) _statusMeta(StockEntry entry) {
    final pending = entry.items
        .where(
          (item) =>
              item.productId == null ||
              item.checkStatus == 'pending_product' ||
              item.checkStatus == 'ambiguous_product',
        )
        .length;
    if (entry.status == 'confirmed') {
      return (
        label: 'Confirmada',
        icon: Icons.check_circle_outline,
        color: const Color(0xff087f5b),
      );
    }
    if (entry.status == 'draft') {
      return (
        label: 'Rascunho',
        icon: Icons.edit_note_outlined,
        color: const Color(0xff64748b),
      );
    }
    if (entry.status == 'reversed') {
      return (
        label: 'Estornada',
        icon: Icons.undo,
        color: const Color(0xff64748b),
      );
    }
    if (pending > 0) {
      return (
        label: 'Aguardando recebimento',
        icon: Icons.link_off,
        color: const Color(0xffb45309),
      );
    }
    if (entry.status == 'receiving') {
      return (
        label: 'Em conferência',
        icon: Icons.fact_check_outlined,
        color: const Color(0xff176b80),
      );
    }
    if (entry.status == 'divergence') {
      return (
        label: 'Com divergência',
        icon: Icons.warning_amber_outlined,
        color: const Color(0xffc2410c),
      );
    }
    return (
      label: 'Aguardando conferência',
      icon: Icons.schedule,
      color: const Color(0xff315dbb),
    );
  }

  String _primaryAction(StockEntry entry) {
    final meta = _statusMeta(entry);
    if (meta.label == 'Aguardando recebimento') return 'Receber';
    if (meta.label == 'Em conferência') return 'Receber';
    if (meta.label == 'Com divergência') return 'Revisar';
    if (meta.label == 'Aguardando conferência') return 'Iniciar conferência';
    return 'Visualizar';
  }

  String _date(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _money(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.all(wide ? 24 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(wide),
                      const SizedBox(height: 18),
                      _searchPanel(wide),
                      const SizedBox(height: 14),
                      Expanded(child: _notesPanel(wide)),
                      if (_total > 0) _pagination(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(bool wide) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recebimento de mercadorias',
              style: TextStyle(
                color: Color(0xff172b4d),
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Central de notas recebidas e próximas ações',
              style: TextStyle(color: Color(0xff64748b), fontSize: 14),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Atualizar'),
          ),
          OutlinedButton.icon(
            onPressed: _openXmlInbox,
            icon: const Icon(Icons.inbox_outlined, size: 18),
            label: const Text('Caixa de XML'),
          ),
          OutlinedButton.icon(
            onPressed: _pickAndUploadXml,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Importar XML'),
          ),
          FilledButton.icon(
            onPressed: _openManualReceiving,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nova entrada manual'),
          ),
          if (wide) ...[
            OutlinedButton.icon(
              onPressed: _canExport ? _exportCurrentQuery : null,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(_exporting ? 'Exportando...' : 'Exportar'),
            ),
          ] else
            PopupMenuButton<String>(
              tooltip: 'Mais ações',
              onSelected: (value) => _showActionMessage(value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'xml', child: Text('Importar XML')),
                PopupMenuItem(value: 'inbox', child: Text('Caixa de XML')),
                PopupMenuItem(
                  value: 'export',
                  child: Text('Exportar consulta'),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.more_horiz),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _searchPanel(bool wide) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onSubmitted: (_) {
              _page = 1;
              _load();
            },
            decoration: InputDecoration(
              hintText:
                  'Pesquisar por número da NF, chave NF-e, fornecedor ou CNPJ',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  _search.clear();
                  _page = 1;
                  _load();
                },
                icon: const Icon(Icons.clear),
              ),
              filled: true,
              fillColor: const Color(0xfff8fafc),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xffd8e0ea)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filter('Período', null, icon: Icons.calendar_today_outlined),
              _filter('Status', _status, icon: Icons.flag_outlined),
              _filter('Fornecedor', null, icon: Icons.local_shipping_outlined),
              _filter('Origem', null, icon: Icons.input_outlined),
              OutlinedButton.icon(
                onPressed: _showMoreFilters,
                icon: const Icon(Icons.tune, size: 18),
                label: Text('Mais filtros'),
              ),
              if (wide) const SizedBox(width: 8),
              if (_selected.isNotEmpty)
                Text(
                  '${_selected.length} selecionada(s)',
                  style: const TextStyle(
                    color: Color(0xff176b80),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _notesPanel(bool wide) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notas para recebimento',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff172b4d),
                  ),
                ),
              ),
              Text(
                '${_summary['receiving'] ?? 0} a receber',
                style: const TextStyle(color: Color(0xff64748b)),
              ),
              const SizedBox(width: 14),
              Text(
                '${_total + _xmlInbox.length} documento(s)',
                style: const TextStyle(color: Color(0xff64748b)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _entries.isEmpty && _xmlInbox.isEmpty
              ? _emptyState()
              : (wide ? _desktopTable() : _mobileRows()),
        ),
      ],
    ),
  );

  Widget _emptyState() => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 42, color: Color(0xff94a3b8)),
          SizedBox(height: 10),
          Text(
            'Nenhuma nota encontrada',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xff334155),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Ajuste os filtros ou importe uma nova entrada.',
            style: TextStyle(color: Color(0xff64748b)),
          ),
        ],
      ),
    ),
  );

  Widget _desktopTable() => SingleChildScrollView(
    child: DataTable(
      showCheckboxColumn: true,
      headingRowColor: WidgetStateProperty.all(const Color(0xfff8fafc)),
      columns: const [
        DataColumn(label: Text('NF')),
        DataColumn(label: Text('Fornecedor')),
        DataColumn(label: Text('Emissão')),
        DataColumn(label: Text('Valor')),
        DataColumn(label: Text('Itens')),
        DataColumn(label: Text('Origem')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Ação')),
        DataColumn(label: Text('')),
      ],
      rows: [..._xmlInbox.map(_xmlDataRow), ..._entries.map(_dataRow)],
    ),
  );

  DataRow _xmlDataRow(XmlInboxMessage message) {
    final pendingSupplier = message.status == 'pending_supplier';
    final pendingMeta = pendingSupplier
        ? (
            label: 'Fornecedor pendente',
            icon: Icons.person_search_outlined,
            color: const Color(0xffb45309),
          )
        : (
            label: 'XML pendente',
            icon: Icons.mark_email_unread_outlined,
            color: const Color(0xffb45309),
          );
    return DataRow(
      cells: [
        DataCell(
          Text(
            message.invoiceNumber ?? message.invoiceKey ?? 'XML #${message.id}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(Text(message.supplierName ?? 'Fornecedor não identificado')),
        DataCell(Text(_date(message.receivedAt))),
        const DataCell(Text('—')),
        const DataCell(Text('—')),
        const DataCell(Text('XML por e-mail')),
        DataCell(_statusChip(pendingMeta)),
        DataCell(
          pendingSupplier
              ? FilledButton.icon(
                  onPressed: () => _registerPendingSupplier(message),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                  label: const Text('Cadastrar fornecedor'),
                )
              : IconButton(
                  tooltip: 'Importar XML',
                  onPressed: () => _importXml(message),
                  icon: const Icon(Icons.file_download_outlined),
                ),
        ),
        const DataCell(SizedBox.shrink()),
      ],
    );
  }

  DataRow _dataRow(StockEntry entry) {
    final meta = _statusMeta(entry);
    return DataRow(
      selected: _selected.contains(entry.id),
      onSelectChanged: (value) => setState(
        () => value == true
            ? _selected.add(entry.id)
            : _selected.remove(entry.id),
      ),
      cells: [
        DataCell(
          Text(
            entry.invoiceNumber ?? '#${entry.id}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(Text(entry.supplierName ?? 'Fornecedor não identificado')),
        DataCell(Text(_date(entry.createdAt))),
        DataCell(Text(_money(entry.totalAmount))),
        DataCell(Text('${entry.items.length}')),
        DataCell(Text(_sourceLabel(entry.source))),
        DataCell(_statusChip(meta)),
        DataCell(
          TextButton(
            onPressed: () => _primaryPressed(entry),
            child: Text(_primaryAction(entry)),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Ações',
            onPressed: () => _showEntryActions(entry),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    );
  }

  Widget _mobileRows() => ListView.separated(
    padding: const EdgeInsets.all(12),
    itemCount: _xmlInbox.length + _entries.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (_, index) => index < _xmlInbox.length
        ? _mobileXmlRow(_xmlInbox[index])
        : _mobileRow(_entries[index - _xmlInbox.length]),
  );

  Widget _mobileXmlRow(XmlInboxMessage message) {
    final pendingSupplier = message.status == 'pending_supplier';
    final meta = pendingSupplier
        ? (
            label: 'Fornecedor pendente',
            icon: Icons.person_search_outlined,
            color: const Color(0xffb45309),
          )
        : (
            label: 'XML pendente',
            icon: Icons.mark_email_unread_outlined,
            color: const Color(0xffb45309),
          );
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'NF ${message.invoiceNumber ?? message.invoiceKey ?? 'sem número'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xff172b4d),
                    ),
                  ),
                ),
                _statusChip(meta),
              ],
            ),
            Text(message.supplierName ?? 'Fornecedor não identificado'),
            const SizedBox(height: 6),
            Text(
              '${_date(message.receivedAt)} • XML recebido por e-mail',
              style: const TextStyle(color: Color(0xff64748b)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: pendingSupplier
                  ? FilledButton.icon(
                      onPressed: () => _registerPendingSupplier(message),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Cadastrar fornecedor'),
                    )
                  : IconButton(
                      tooltip: 'Importar XML',
                      onPressed: () => _importXml(message),
                      icon: const Icon(Icons.file_download_outlined),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileRow(StockEntry entry) {
    final meta = _statusMeta(entry);
    return Card(
      elevation: 0,
      child: InkWell(
        onTap: () => _showEntry(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _selected.contains(entry.id),
                    onChanged: (value) => setState(
                      () => value == true
                          ? _selected.add(entry.id)
                          : _selected.remove(entry.id),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'NF ${entry.invoiceNumber ?? entry.id}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xff172b4d),
                      ),
                    ),
                  ),
                  _statusChip(meta),
                ],
              ),
              Text(entry.supplierName ?? 'Fornecedor não identificado'),
              const SizedBox(height: 6),
              Text(
                '${_date(entry.createdAt)} • ${entry.items.length} item(ns) • ${_money(entry.totalAmount)}',
                style: const TextStyle(color: Color(0xff64748b)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _primaryPressed(entry),
                  child: Text(_primaryAction(entry)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(({String label, IconData icon, Color color}) meta) => Chip(
    avatar: Icon(meta.icon, size: 16, color: meta.color),
    label: Text(meta.label),
    labelStyle: TextStyle(
      color: meta.color,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    backgroundColor: meta.color.withValues(alpha: .10),
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
  );

  Widget _pagination() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text('Página $_page', style: const TextStyle(color: Color(0xff64748b))),
      IconButton(
        onPressed: _page > 1
            ? () {
                _page--;
                _load();
              }
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        onPressed: _page * 25 < _total
            ? () {
                _page++;
                _load();
              }
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  String _sourceLabel(String source) => switch (source) {
    'xml' => 'XML',
    'email_xml' => 'XML',
    'mobile' => 'Aplicativo',
    'purchase_order' => 'Pedido',
    _ => 'Manual',
  };

  void _primaryPressed(StockEntry entry) {
    if (entry.status != 'confirmed' && entry.status != 'reversed') {
      Navigator.of(context)
          .push<bool>(
            MaterialPageRoute(
              builder: (_) => ReceivingConferenceScreen(
                session: widget.session,
                entryId: entry.id,
              ),
            ),
          )
          .then((_) => _load());
      return;
    }
    _showEntry(entry);
  }

  void _showActionMessage(String action) {
    final message = switch (action) {
      'xml' => 'A importação de XML continua disponível em Nova entrada.',
      'inbox' => 'A caixa de XML será aberta neste fluxo.',
      'export' => 'A exportação respeitará a consulta atual.',
      'columns' => 'A configuração de colunas será salva por usuário.',
      _ => 'A conferência será iniciada pelo fluxo seguro.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showMoreFilters() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Mais filtros',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('Notas vindas de XML'),
              subtitle: const Text('Exibe entradas criadas a partir de XML'),
              onTap: () => Navigator.pop(context, 'xml'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Aguardando conferência'),
              onTap: () => Navigator.pop(context, 'receiving'),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('Com divergência'),
              onTap: () => Navigator.pop(context, 'divergence'),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Limpar filtros'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (selected == 'clear') {
        _status = null;
        _source = null;
        _supplierId = null;
        _periodDays = null;
        _fromDate = null;
        _toDate = null;
        _search.clear();
      } else if (selected == 'xml') {
        _source = 'xml';
      } else {
        _status = selected;
      }
      _page = 1;
    });
    _load();
  }

  Future<DateTimeRange?> _showCompactDateRangeDialog() async {
    String formatDate(DateTime? date) => date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    DateTime? parseDate(String value) {
      final parts = value.trim().split('/');
      if (parts.length != 3) return null;
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day == null || month == null || year == null) return null;
      final result = DateTime(year, month, day);
      return result.year == year && result.month == month && result.day == day
          ? result
          : null;
    }

    final start = TextEditingController(text: formatDate(_fromDate));
    final end = TextEditingController(text: formatDate(_toDate));
    String? error;
    try {
      return await showDialog<DateTimeRange>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            void applyQuick(Duration duration) {
              final today = DateTime.now();
              final from = today.subtract(duration);
              start.text = formatDate(from);
              end.text = formatDate(today);
              setDialogState(() => error = null);
            }

            Future<void> pickDate({required bool isStart}) async {
              final controller = isStart ? start : end;
              final selected = parseDate(controller.text) ?? DateTime.now();
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: selected,
                firstDate: DateTime(2000),
                lastDate: DateTime(DateTime.now().year + 20),
                helpText: isStart
                    ? 'Selecionar data inicial'
                    : 'Selecionar data final',
                cancelText: 'Cancelar',
                confirmText: 'Selecionar',
              );
              if (picked == null) return;
              setDialogState(() {
                controller.text = formatDate(picked);
                error = null;
              });
            }

            return AlertDialog(
              title: const Text('Filtrar por período'),
              content: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Escolha o período da data de entrada registrada.',
                      style: TextStyle(color: Color(0xff64748b)),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: start,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: 'Data inicial',
                              hintText: 'dd/mm/aaaa',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Abrir calendário',
                                icon: const Icon(Icons.calendar_today_outlined),
                                onPressed: () => pickDate(isStart: true),
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('até'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: end,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: 'Data final',
                              hintText: 'dd/mm/aaaa',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Abrir calendário',
                                icon: const Icon(Icons.calendar_today_outlined),
                                onPressed: () => pickDate(isStart: false),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Hoje'),
                          onPressed: () => applyQuick(Duration.zero),
                        ),
                        ActionChip(
                          label: const Text('Últimos 7 dias'),
                          onPressed: () => applyQuick(const Duration(days: 7)),
                        ),
                        ActionChip(
                          label: const Text('Últimos 30 dias'),
                          onPressed: () => applyQuick(const Duration(days: 30)),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xffb42318)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    DateTimeRange(start: DateTime(2000), end: DateTime(2000)),
                  ),
                  child: const Text('Limpar'),
                ),
                FilledButton(
                  onPressed: () {
                    final from = parseDate(start.text);
                    final to = parseDate(end.text);
                    if (from == null || to == null) {
                      error = 'Informe as duas datas no formato dd/mm/aaaa.';
                      setDialogState(() {});
                      return;
                    }
                    if (from.isAfter(to)) {
                      error =
                          'A data inicial não pode ser maior que a data final.';
                      setDialogState(() {});
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      DateTimeRange(start: from, end: to),
                    );
                  },
                  child: const Text('Aplicar período'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      start.dispose();
      end.dispose();
    }
  }

  Widget _filter(String label, String? status, {IconData? icon}) =>
      OutlinedButton.icon(
        icon: Icon(icon ?? Icons.arrow_drop_down, size: 17),
        label: Text(status == null ? label : _statusLabel(status)),
        onPressed: () async {
          if (label == 'Origem') {
            final selected = await showMenu<String>(
              context: context,
              position: const RelativeRect.fromLTRB(500, 220, 0, 0),
              items: const [
                PopupMenuItem(value: 'all', child: Text('Todas as origens')),
                PopupMenuItem(value: 'xml', child: Text('XML')),
                PopupMenuItem(value: 'manual', child: Text('Manual')),
                PopupMenuItem(value: 'mobile', child: Text('Aplicativo')),
              ],
            );
            if (!mounted || selected == null) return;
            setState(() {
              _source = selected == 'all' ? null : selected;
              _page = 1;
            });
            _load();
            return;
          }
          if (label == 'Fornecedor') {
            List<Supplier> suppliers;
            try {
              suppliers = (await _api.listSuppliers(
                widget.session.token,
              )).where((supplier) => supplier.active).toList();
            } on ApiException catch (error) {
              if (mounted) _showActionMessage(error.message);
              return;
            }
            if (!mounted) return;
            final selected = await showMenu<int>(
              context: context,
              position: const RelativeRect.fromLTRB(380, 220, 0, 0),
              items: suppliers
                  .map(
                    (supplier) => PopupMenuItem(
                      value: supplier.id,
                      child: Text(supplier.name),
                    ),
                  )
                  .toList(),
            );
            if (!mounted || selected == null) return;
            setState(() {
              _supplierId = selected;
              _page = 1;
            });
            _load();
            return;
          }
          if (label == 'Período') {
            final selected = await _showCompactDateRangeDialog();
            if (!mounted || selected == null) return;
            if (selected.start.year == 2000 && selected.end.year == 2000) {
              setState(() {
                _fromDate = null;
                _toDate = null;
                _periodDays = null;
                _page = 1;
              });
              _load();
              return;
            }
            setState(() {
              _periodDays = null;
              _fromDate = DateTime(
                selected.start.year,
                selected.start.month,
                selected.start.day,
              );
              _toDate = DateTime(
                selected.end.year,
                selected.end.month,
                selected.end.day,
                23,
                59,
                59,
              );
              _page = 1;
            });
            _load();
            return;
          }
          final selected = await showMenu<String>(
            context: context,
            position: const RelativeRect.fromLTRB(260, 220, 0, 0),
            items: const [
              PopupMenuItem(value: 'all', child: Text('Todos os status')),
              PopupMenuItem(
                value: 'awaiting_products',
                child: Text('Aguardando conciliação'),
              ),
              PopupMenuItem(value: 'receiving', child: Text('Em conferência')),
              PopupMenuItem(
                value: 'divergence',
                child: Text('Com divergência'),
              ),
              PopupMenuItem(value: 'confirmed', child: Text('Confirmadas')),
            ],
          );
          if (!mounted || selected == null) return;
          setState(() {
            _status = selected == 'all' ? null : selected;
            _page = 1;
          });
          _load();
        },
      );

  void _showEntry(StockEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Entrada #${entry.id}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(entry.supplierName ?? 'Fornecedor não identificado'),
              const Divider(),
              ...entry.items.map(
                (item) => ListTile(
                  dense: true,
                  leading: Icon(
                    item.productId == null ? Icons.help_outline : Icons.check,
                    color: item.productId == null
                        ? Colors.orange
                        : Colors.green,
                  ),
                  title: Text(item.description),
                  subtitle: Text(
                    'Esperado: ${item.quantity} ${item.unit} • '
                    'Conferido: ${item.receivedQuantity ?? 0} ${item.unit}',
                  ),
                  trailing: item.productId == null
                      ? TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _matchProduct(entry, item);
                          },
                          child: const Text('Vincular'),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              if (entry.status != 'confirmed' &&
                  entry.status != 'reversed') ...[
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _reprocess(entry);
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Reprocessar conciliação'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _confirm(entry),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirmar entrada'),
                ),
              ],
              if (entry.status == 'confirmed' && _canReverseEntries)
                OutlinedButton.icon(
                  onPressed: () => _reverse(entry),
                  icon: const Icon(Icons.undo),
                  label: const Text('Solicitar estorno'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEntryActions(StockEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ações da entrada #${entry.id}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                "${entry.invoiceNumber ?? 'Sem número'} • ${entry.supplierName ?? 'Fornecedor não identificado'}",
                style: const TextStyle(color: Color(0xff64748b)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Visualizar detalhes'),
                subtitle: const Text(
                  'Itens, quantidades e situação da entrada',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEntry(entry);
                },
              ),
              if (entry.status != 'confirmed' && entry.status != 'reversed')
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Abrir conferência'),
                  subtitle: const Text(
                    'Conferir produtos recebidos e divergências',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showEntry(entry);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Ver histórico da entrada'),
                subtitle: const Text('Usuários, associações e confirmações'),
                onTap: () {
                  Navigator.pop(context);
                  _showAudit(entry);
                },
              ),
              if (entry.status != 'confirmed' && entry.status != 'reversed')
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Reprocessar conciliação'),
                  onTap: () {
                    Navigator.pop(context);
                    _reprocess(entry);
                  },
                ),
              if (entry.status != 'confirmed' && entry.status != 'reversed')
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Confirmar entrada'),
                  onTap: () {
                    Navigator.pop(context);
                    _confirm(entry);
                  },
                ),
              if (entry.status == 'confirmed' && _canReverseEntries)
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Solicitar estorno'),
                  onTap: () {
                    Navigator.pop(context);
                    _reverse(entry);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

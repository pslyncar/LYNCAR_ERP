import 'package:flutter/material.dart';

import '../view_models/operations_view_model.dart';

class PrinterSettingsView extends StatefulWidget {
  const PrinterSettingsView({super.key, required this.viewModel});
  final OperationsViewModel viewModel;

  @override
  State<PrinterSettingsView> createState() => _PrinterSettingsViewState();
}

class _PrinterSettingsViewState extends State<PrinterSettingsView> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.viewModel.loadPrinters();
    if (!mounted) return;
    setState(() {
      data = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final installed = (data?['installed'] as List<dynamic>? ?? const [])
        .map((item) => '$item')
        .toList(growable: false);
    final bindings = (data?['bindings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Impressoras',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'O ERP define para onde cada produto vai. Neste computador você liga cada destino à impressora física.',
          ),
          const SizedBox(height: 20),
          _DestinationCard(
            logicalKey: 'cashier',
            logicalName: 'Impressora do caixa',
            installed: installed,
            binding: _binding(bindings, 'cashier'),
            viewModel: widget.viewModel,
            onSaved: _load,
          ),
          const SizedBox(height: 12),
          _DestinationCard(
            logicalKey: 'station:kitchen',
            logicalName: 'Cozinha principal',
            installed: installed,
            binding: _binding(bindings, 'station:kitchen'),
            viewModel: widget.viewModel,
            onSaved: _load,
          ),
          for (final binding in bindings)
            if (binding['logical_key'] != 'cashier' &&
                binding['logical_key'] != 'station:kitchen') ...[
              const SizedBox(height: 12),
              _DestinationCard(
                logicalKey: '${binding['logical_key']}',
                logicalName: '${binding['logical_name']}',
                installed: installed,
                binding: binding,
                viewModel: widget.viewModel,
                onSaved: _load,
              ),
            ],
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      installed.isEmpty
                          ? 'O Windows não informou impressoras instaladas. Instale ou compartilhe a impressora e atualize esta tela.'
                          : 'Uma impressora pode atender caixa e cozinha. Cada item gera apenas um cupom no destino configurado no ERP.',
                    ),
                  ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _binding(
    List<Map<String, dynamic>> bindings,
    String key,
  ) {
    for (final binding in bindings) {
      if (binding['logical_key'] == key) return binding;
    }
    return null;
  }
}

class _DestinationCard extends StatefulWidget {
  const _DestinationCard({
    required this.logicalKey,
    required this.logicalName,
    required this.installed,
    required this.binding,
    required this.viewModel,
    required this.onSaved,
  });
  final String logicalKey;
  final String logicalName;
  final List<String> installed;
  final Map<String, dynamic>? binding;
  final OperationsViewModel viewModel;
  final VoidCallback onSaved;

  @override
  State<_DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends State<_DestinationCard> {
  String? printer;
  int copies = 1;
  bool automatic = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final configured = widget.binding?['printer_name']?.toString();
    printer = widget.installed.contains(configured) ? configured : null;
    copies = widget.binding?['copies'] as int? ?? 1;
    automatic = widget.binding?['auto_print'] as bool? ?? true;
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.print_outlined),
              title: Text(widget.logicalName),
              subtitle: Text(widget.logicalKey),
            ),
          ),
          SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              initialValue: printer,
              decoration: const InputDecoration(
                labelText: 'Impressora do Windows',
              ),
              items: [
                for (final item in widget.installed)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (value) => setState(() => printer = value),
            ),
          ),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<int>(
              initialValue: copies,
              decoration: const InputDecoration(labelText: 'Vias'),
              items: [
                for (var value = 1; value <= 3; value++)
                  DropdownMenuItem(value: value, child: Text('$value')),
              ],
              onChanged: (value) => setState(() => copies = value ?? 1),
            ),
          ),
          FilterChip(
            selected: automatic,
            label: const Text('Impressão automática'),
            onSelected: (value) => setState(() => automatic = value),
          ),
          OutlinedButton.icon(
            onPressed: printer == null
                ? null
                : () async {
                    final ok = await widget.viewModel.testPrinter(
                      printer!,
                      widget.logicalName,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'Teste enviado.' : 'Falha no teste.',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Testar'),
          ),
          FilledButton.icon(
            onPressed: printer == null || saving
                ? null
                : () async {
                    setState(() => saving = true);
                    final ok = await widget.viewModel.savePrinterBinding(
                      logicalKey: widget.logicalKey,
                      logicalName: widget.logicalName,
                      printerName: printer!,
                      copies: copies,
                      autoPrint: automatic,
                    );
                    if (!mounted) return;
                    setState(() => saving = false);
                    if (ok) widget.onSaved();
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

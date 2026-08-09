import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/dashboard_summary.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class DashboardContentsScreen extends StatefulWidget {
  const DashboardContentsScreen({
    super.key,
    required this.session,
    required this.title,
    required this.subtitle,
    required this.allowedTypes,
    this.defaultType = 'notice',
  });

  final Session session;
  final String title;
  final String subtitle;
  final List<String> allowedTypes;
  final String defaultType;

  @override
  State<DashboardContentsScreen> createState() =>
      _DashboardContentsScreenState();
}

class _DashboardContentsScreenState extends State<DashboardContentsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<DashboardContent> _contents = [];
  final _search = TextEditingController();
  String _statusFilter = 'ativos';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadContents() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contents = await _api.listMasterDashboardContents(
        widget.session.token,
      );
      setState(() => _contents = contents);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar a vitrine.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([DashboardContent? content]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _DashboardContentDialog(
        api: _api,
        token: widget.session.token,
        content: content,
        allowedTypes: widget.allowedTypes,
        defaultType: widget.defaultType,
      ),
    );
    if (saved == true) {
      await _loadContents();
    }
  }

  Future<void> _deleteContent(DashboardContent content) async {
    await _api.deleteMasterDashboardContent(widget.session.token, content.id);
    await _loadContents();
  }

  @override
  Widget build(BuildContext context) {
    final filteredContents = _filteredContents();
    return ColoredBox(
      color: const Color(0xFFF4F7FB),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loadContents,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Atualizar'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo card'),
                ),
              ],
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
                        labelText: 'Buscar cards',
                        hintText: 'Titulo, descricao, segmento, link...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'ativos',
                          child: Text('Ativos'),
                        ),
                        DropdownMenuItem(
                          value: 'inativos',
                          child: Text('Inativos'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _statusFilter = value ?? 'ativos'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Limpar busca',
                    onPressed: () => setState(() {
                      _search.clear();
                      _statusFilter = 'ativos';
                    }),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _loadContents)
            else
              _ContentsTable(
                contents: filteredContents,
                onEdit: _openForm,
                onDelete: _deleteContent,
              ),
          ],
        ),
      ),
    );
  }

  List<DashboardContent> _filteredContents() {
    final term = _normalize(_search.text);
    return _contents.where((content) {
      if (!widget.allowedTypes.contains(content.contentType)) return false;
      if (_statusFilter == 'ativos' && !content.active) return false;
      if (_statusFilter == 'inativos' && content.active) return false;
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          content.title,
          content.description,
          content.badge,
          content.priceLabel,
          content.targetUrl,
          content.buttonLabel,
          content.segment,
          content.contentType,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }
}

class _ContentsTable extends StatelessWidget {
  const _ContentsTable({
    required this.contents,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DashboardContent> contents;
  final ValueChanged<DashboardContent> onEdit;
  final ValueChanged<DashboardContent> onDelete;

  @override
  Widget build(BuildContext context) {
    if (contents.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhum card cadastrado ainda.'),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ResponsiveDataTable(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Titulo')),
            DataColumn(label: Text('Segmento')),
            DataColumn(label: Text('Ordem')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Acoes')),
          ],
          rows: [
            for (final content in contents)
              DataRow(
                cells: [
                  DataCell(Text(_typeLabel(content.contentType))),
                  DataCell(Text(content.title)),
                  DataCell(Text(content.segment ?? 'todos')),
                  DataCell(Text('${content.sortOrder}')),
                  DataCell(Text(content.active ? 'Ativo' : 'Inativo')),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => onEdit(content),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          onPressed: () => onDelete(content),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'certificate' => 'Certificado A1',
      'product' => 'Produto',
      'affiliate_link' => 'Link afiliado',
      _ => 'Aviso',
    };
  }
}

class _DashboardContentDialog extends StatefulWidget {
  const _DashboardContentDialog({
    required this.api,
    required this.token,
    required this.allowedTypes,
    required this.defaultType,
    this.content,
  });

  final ApiClient api;
  final String token;
  final List<String> allowedTypes;
  final String defaultType;
  final DashboardContent? content;

  @override
  State<_DashboardContentDialog> createState() =>
      _DashboardContentDialogState();
}

class _DashboardContentDialogState extends State<_DashboardContentDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _type = widget.content?.contentType ?? widget.defaultType;
  late bool _active = widget.content?.active ?? true;
  late final _title = TextEditingController(text: widget.content?.title ?? '');
  late final _description = TextEditingController(
    text: widget.content?.description ?? '',
  );
  late final _badge = TextEditingController(text: widget.content?.badge ?? '');
  late final _price = TextEditingController(
    text: widget.content?.priceLabel ?? '',
  );
  late final _imageUrl = TextEditingController(
    text: widget.content?.imageUrl ?? '',
  );
  late final _targetUrl = TextEditingController(
    text: widget.content?.targetUrl ?? '',
  );
  late final _button = TextEditingController(
    text: widget.content?.buttonLabel ?? '',
  );
  late final _segment = TextEditingController(
    text: widget.content?.segment ?? 'todos',
  );
  late final _sortOrder = TextEditingController(
    text: '${widget.content?.sortOrder ?? 0}',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _badge.dispose();
    _price.dispose();
    _imageUrl.dispose();
    _targetUrl.dispose();
    _button.dispose();
    _segment.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = DashboardContentPayload(
      contentType: _type,
      title: _title.text.trim(),
      description: _emptyToNull(_description.text),
      badge: _emptyToNull(_badge.text),
      priceLabel: _emptyToNull(_price.text),
      imageUrl: _emptyToNull(_imageUrl.text),
      targetUrl: _emptyToNull(_targetUrl.text),
      buttonLabel: _emptyToNull(_button.text),
      segment: _emptyToNull(_segment.text),
      sortOrder: int.tryParse(_sortOrder.text) ?? 0,
      active: _active,
    );
    try {
      if (widget.content == null) {
        await widget.api.createMasterDashboardContent(widget.token, payload);
      } else {
        await widget.api.updateMasterDashboardContent(
          widget.token,
          widget.content!.id,
          payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      final url = await widget.api.uploadImage(
        widget.token,
        bytes: bytes,
        filename: file.name,
        master: true,
      );
      setState(() => _imageUrl.text = url);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível enviar a imagem.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.content == null ? 'Novo card' : 'Editar card'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items:
                      const [
                            DropdownMenuItem(
                              value: 'notice',
                              child: Text('Aviso'),
                            ),
                            DropdownMenuItem(
                              value: 'certificate',
                              child: Text('Certificado A1'),
                            ),
                            DropdownMenuItem(
                              value: 'product',
                              child: Text('Produto'),
                            ),
                            DropdownMenuItem(
                              value: 'affiliate_link',
                              child: Text('Link afiliado'),
                            ),
                          ]
                          .where(
                            (item) => widget.allowedTypes.contains(item.value),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => _type = value!),
                ),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Titulo'),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Informe o titulo.'
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Descricao'),
                  minLines: 2,
                  maxLines: 3,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _badge,
                        decoration: const InputDecoration(labelText: 'Selo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(
                          labelText: 'Preço/texto comercial',
                        ),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _targetUrl,
                  decoration: const InputDecoration(
                    labelText: 'Link de destino',
                    hintText: 'https://...',
                  ),
                ),
                TextFormField(
                  controller: _button,
                  decoration: const InputDecoration(
                    labelText: 'Texto do botao',
                  ),
                ),
                TextFormField(
                  controller: _imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'URL da imagem opcional',
                  ),
                ),
                const SizedBox(height: 10),
                _ImagePickerPanel(
                  imageUrl: _imageUrl.text,
                  apiBaseUrl: widget.api.baseUrl,
                  onPick: _saving ? null : _pickImage,
                  onClear: _saving
                      ? null
                      : () => setState(() => _imageUrl.clear()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _segment,
                        decoration: const InputDecoration(
                          labelText: 'Segmento',
                          hintText: 'todos, padaria, mercado...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _sortOrder,
                        decoration: const InputDecoration(labelText: 'Ordem'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Ativo'),
                ),
              ],
            ),
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
          label: const Text('Salvar'),
        ),
      ],
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _ImagePickerPanel extends StatelessWidget {
  const _ImagePickerPanel({
    required this.imageUrl,
    required this.apiBaseUrl,
    required this.onPick,
    required this.onClear,
  });

  final String imageUrl;
  final String apiBaseUrl;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final url = _publicUrl(apiBaseUrl, imageUrl);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: 86,
                height: 72,
                color: Colors.white,
                child: url == null
                    ? const Icon(Icons.image_outlined, color: Color(0xFF64748B))
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFF64748B),
                            ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                url == null
                    ? 'Selecione uma foto para aviso, certificado ou item da loja.'
                    : imageUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Foto'),
            ),
            if (url != null)
              IconButton(
                tooltip: 'Remover imagem',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

String? _publicUrl(String apiBaseUrl, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$base$path';
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

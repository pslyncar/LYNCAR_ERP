import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/fiscal.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class FiscalScreen extends StatefulWidget {
  const FiscalScreen({super.key, required this.session});

  final Session session;

  @override
  State<FiscalScreen> createState() => _FiscalScreenState();
}

class _FiscalScreenState extends State<FiscalScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  CompanyFiscalSetting? _settings;
  FiscalSetupChecklist? _checklist;
  RtcCompliance? _rtcCompliance;
  List<FiscalOutputRule> _outputRules = const [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _syncingNfceNumbering = false;
  bool _recoveringFiscalDocuments = false;

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
      final settings = await _api.getFiscalSettings(widget.session.token);
      final outputRules = await _api.listFiscalOutputRules(
        widget.session.token,
      );
      FiscalSetupChecklist? checklist;
      try {
        checklist = await _api.getFiscalSetupChecklist(widget.session.token);
      } on ApiException {
        // O checklist ajuda a implantacao, mas nao bloqueia a tela principal.
      }

      RtcCompliance? rtcCompliance;
      try {
        rtcCompliance = await _api.getRtcCompliance(widget.session.token);
      } on ApiException {
        // Esta consulta e complementar e nunca deve ocultar os dados fiscais.
      }

      if (!mounted) return;
      setState(() {
        _settings = settings;
        _checklist = checklist;
        _rtcCompliance = rtcCompliance;
        _outputRules = outputRules;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar o módulo fiscal.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        'Fiscal',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Certificado A1, CSC/ID, séries e cadastro tributário',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            if (_error != null) ...[
              ErrorPanel(message: _error!, onRetry: _load),
              const SizedBox(height: 14),
            ],
            _FiscalSetupChecklistCard(checklist: _checklist),
            const SizedBox(height: 14),
            _SettingsCard(
              settings: _settings,
              canManage: widget.session.can('fiscal:settings'),
              saving: _saving,
              onToggleNfce: (value) => _saveSettings(nfceEnabled: value),
              onTogglePdvNfce: (value) => _saveSettings(pdvNfceEnabled: value),
              onToggleNfe: (value) => _saveSettings(nfeEnabled: value),
              onEditCompanyData: _editCompanyFiscalData,
              onSaveCsc: _saveCsc,
              onUploadCertificate: _uploadCertificate,
              onDeleteCertificate: _deleteCertificate,
              syncingNfceNumbering: _syncingNfceNumbering,
              onSyncNfceNumbering: _syncNfceNumbering,
              recoveringFiscalDocuments: _recoveringFiscalDocuments,
              onRecoverFiscalDocuments: _recoverFiscalDocuments,
            ),
            const SizedBox(height: 14),
            _RtcCompliancePanel(compliance: _rtcCompliance),
            const SizedBox(height: 14),
            _FiscalOutputRulesCard(
              rules: _outputRules,
              canManage: widget.session.can('fiscal:settings'),
              saving: _saving,
              onCreate: () => _editOutputRule(),
              onEdit: _editOutputRule,
              onDelete: _deleteOutputRule,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings({
    bool? nfceEnabled,
    bool? pdvNfceEnabled,
    bool? nfeEnabled,
  }) async {
    final current = _settings;
    if (current == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updateFiscalSettings(widget.session.token, {
        'nfce_enabled': nfceEnabled ?? current.nfceEnabled,
        'pdv_nfce_enabled': pdvNfceEnabled ?? current.pdvNfceEnabled,
        'nfe_enabled': nfeEnabled ?? current.nfeEnabled,
      });
      setState(() => _settings = updated);
      await _refreshChecklist();
      await _refreshChecklist();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshChecklist() async {
    try {
      final checklist = await _api.getFiscalSetupChecklist(widget.session.token);
      if (mounted) setState(() => _checklist = checklist);
    } on ApiException {
      // Mantem o ultimo checklist visivel se a consulta complementar falhar.
    }
  }

  Future<void> _editCompanyFiscalData() async {
    final current = _settings;
    if (current == null) return;
    final legalName = TextEditingController(text: current.legalName ?? '');
    final tradeName = TextEditingController(text: current.tradeName ?? '');
    final cnpj = TextEditingController(text: current.cnpj ?? '');
    final stateRegistration = TextEditingController(
      text: current.stateRegistration ?? '',
    );
    final municipalRegistration = TextEditingController(
      text: current.municipalRegistration ?? '',
    );
    final crt = TextEditingController(text: current.crt ?? '1');
    final taxRegime = TextEditingController(text: current.taxRegime ?? '');
    final uf = TextEditingController(text: current.uf ?? 'SP');
    final cityCode = TextEditingController(text: current.cityCode ?? '');
    final addressLine = TextEditingController(text: current.addressLine ?? '');
    final addressNumber = TextEditingController(
      text: current.addressNumber ?? '',
    );
    final neighborhood = TextEditingController(
      text: current.neighborhood ?? '',
    );
    final city = TextEditingController(text: current.city ?? '');
    final zipCode = TextEditingController(text: current.zipCode ?? '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dados fiscais da empresa'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: legalName,
                    decoration: const InputDecoration(
                      labelText: 'Razão social',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tradeName,
                    decoration: const InputDecoration(
                      labelText: 'Nome fantasia',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: municipalRegistration,
                          decoration: const InputDecoration(
                            labelText: 'Inscricao municipal',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: taxRegime,
                          decoration: const InputDecoration(
                            labelText: 'Regime tributario',
                            helperText: 'mei, simples_nacional, regime_normal',
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
                          controller: cnpj,
                          decoration: const InputDecoration(
                            labelText: 'CNPJ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: stateRegistration,
                          decoration: const InputDecoration(
                            labelText: 'Inscrição estadual',
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
                        flex: 3,
                        child: TextField(
                          controller: addressLine,
                          decoration: const InputDecoration(
                            labelText: 'Logradouro',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: addressNumber,
                          decoration: const InputDecoration(
                            labelText: 'Número',
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
                          controller: neighborhood,
                          decoration: const InputDecoration(
                            labelText: 'Bairro',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: city,
                          decoration: const InputDecoration(
                            labelText: 'Cidade',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: zipCode,
                          decoration: const InputDecoration(
                            labelText: 'CEP',
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
                          controller: crt,
                          decoration: const InputDecoration(
                            labelText: 'CRT',
                            helperText:
                                '1 Simples, 2 excesso, 3 normal, 4 MEI',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: uf,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'UF',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: cityCode,
                          decoration: const InputDecoration(
                            labelText: 'Codigo IBGE cidade',
                            helperText: 'Leme/SP: 3526704',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      final updated = await _api.updateFiscalSettings(widget.session.token, {
        'legal_name': legalName.text.trim().isEmpty
            ? null
            : legalName.text.trim(),
        'trade_name': tradeName.text.trim().isEmpty
            ? null
            : tradeName.text.trim(),
        'cnpj': cnpj.text.trim().isEmpty ? null : cnpj.text.trim(),
        'state_registration': stateRegistration.text.trim().isEmpty
            ? null
            : stateRegistration.text.trim(),
        'municipal_registration': municipalRegistration.text.trim().isEmpty
            ? null
            : municipalRegistration.text.trim(),
        'crt': crt.text.trim().isEmpty ? null : crt.text.trim(),
        'tax_regime': taxRegime.text.trim().isEmpty
            ? null
            : taxRegime.text.trim(),
        'uf': uf.text.trim().isEmpty ? null : uf.text.trim().toUpperCase(),
        'city_code': cityCode.text.trim().isEmpty ? null : cityCode.text.trim(),
        'address_line': addressLine.text.trim().isEmpty
            ? null
            : addressLine.text.trim(),
        'address_number': addressNumber.text.trim().isEmpty
            ? null
            : addressNumber.text.trim(),
        'neighborhood': neighborhood.text.trim().isEmpty
            ? null
            : neighborhood.text.trim(),
        'city': city.text.trim().isEmpty ? null : city.text.trim(),
        'zip_code': zipCode.text.trim().isEmpty ? null : zipCode.text.trim(),
      });
      setState(() => _settings = updated);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      legalName.dispose();
      tradeName.dispose();
      cnpj.dispose();
      stateRegistration.dispose();
      municipalRegistration.dispose();
      crt.dispose();
      taxRegime.dispose();
      uf.dispose();
      cityCode.dispose();
      addressLine.dispose();
      addressNumber.dispose();
      neighborhood.dispose();
      city.dispose();
      zipCode.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCsc() async {
    final current = _settings;
    if (current == null) return;
    final cscId = TextEditingController(text: current.nfceCscId ?? '');
    final cscToken = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('CSC / Token NFC-e'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cscId,
                  decoration: const InputDecoration(
                    labelText: 'ID do CSC',
                    prefixIcon: Icon(Icons.tag_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cscToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: current.hasNfceCsc
                        ? 'Novo CSC / Token (deixe vazio para manter)'
                        : 'CSC / Token',
                    prefixIcon: const Icon(Icons.key_outlined),
                    border: const OutlineInputBorder(),
                    helperText: 'O token não aparece de volta depois de salvo.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      final payload = <String, dynamic>{
        'nfce_csc_id': cscId.text.trim().isEmpty ? null : cscId.text.trim(),
      };
      if (cscToken.text.trim().isNotEmpty) {
        payload['nfce_csc_secret_key'] = cscToken.text.trim();
      }
      final updated = await _api.updateFiscalSettings(
        widget.session.token,
        payload,
      );
      setState(() => _settings = updated);
      await _refreshChecklist();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      cscId.dispose();
      cscToken.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadCertificate() async {
    final password = TextEditingController();
    try {
      final fileResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pfx', 'p12'],
        withData: true,
      );
      if (fileResult == null || fileResult.files.single.bytes == null) return;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Senha do certificado A1'),
          content: TextField(
            controller: password,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha do .pfx/.p12',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.upload_file),
              label: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (confirmed != true || password.text.trim().isEmpty) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      final file = fileResult.files.single;
      await _api.uploadFiscalCertificate(
        widget.session.token,
        bytes: file.bytes!,
        filename: file.name,
        password: password.text,
      );
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      password.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCertificate() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.deleteFiscalCertificate(widget.session.token);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNfceNumbering() async {
    final current = _settings;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar numeraÃ§Ã£o NFC-e'),
        content: Text(
          'O sistema vai consultar a NFCeListagemChaves da SEFAZ-SP em homologacao, '
          'identificar o maior nÃºmero autorizado da sÃ©rie ${current.nfceSeries} '
          'e gravar a prÃ³xima NFC-e sem reduzir a sequÃªncia atual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _syncingNfceNumbering = true;
      _error = null;
    });
    try {
      final result = await _api.syncNfceNumbering(widget.session.token);
      await _load();
      if (!mounted) return;
      final warning = result.incomplete
          ? '\n\nA SEFAZ indicou lista incompleta. Reduza o periodo ou repita a consulta para conferir tudo.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NFC-e serie ${result.series}: maior autorizada '
            '${result.highestAuthorizedNumber?.toString() ?? 'nao encontrada'}; '
            'proxima gravada ${result.updatedNextNumber}.$warning',
          ),
        ),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _syncingNfceNumbering = false);
    }
  }

  Future<void> _recoverFiscalDocuments() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar notas da SEFAZ'),
        content: const Text(
          'O sistema vai buscar NFC-e emitidas na SEFAZ-SP, baixar os XMLs disponiveis e tentar consultar NF-e no Ambiente Nacional. As chaves encontradas entram em Notas fiscais.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.cloud_sync_outlined),
            label: const Text('Recuperar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _recoveringFiscalDocuments = true;
      _error = null;
    });
    try {
      final result = await _api.recoverFiscalDocumentsFromSefaz(
        widget.session.token,
      );
      await _load();
      if (!mounted) return;
      final messages = (result['messages'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .join(' | ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importadas ${result['imported'] ?? 0}, atualizadas ${result['updated'] ?? 0}. '
            'NFC-e: ${result['nfce_downloaded'] ?? 0}/${result['nfce_keys'] ?? 0}. '
            'NF-e: ${result['nfe_docs'] ?? 0}. $messages',
          ),
        ),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _recoveringFiscalDocuments = false);
    }
  }

  Future<void> _editOutputRule([FiscalOutputRule? rule]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _FiscalOutputRuleDialog(rule: rule, settings: _settings),
    );
    if (result == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (rule == null) {
        await _api.createFiscalOutputRule(widget.session.token, result);
      } else {
        await _api.updateFiscalOutputRule(
          widget.session.token,
          rule.id,
          result,
        );
      }
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteOutputRule(FiscalOutputRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir regra fiscal?'),
        content: Text(
          'A regra "${rule.name}" deixara de ser usada nas proximas emissoes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.deleteFiscalOutputRule(widget.session.token, rule.id);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _FiscalSetupChecklistCard extends StatelessWidget {
  const _FiscalSetupChecklistCard({required this.checklist});

  final FiscalSetupChecklist? checklist;

  @override
  Widget build(BuildContext context) {
    final item = checklist;
    if (item == null) {
      return const AppCard(
        child: Text(
          'Checklist fiscal indisponivel no momento.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }
    final pendingCount = item.items.where((entry) => entry.status != 'ok').length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Status fiscal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              _ReadinessPill(label: 'NF-e', ready: item.readyForNfe),
              const SizedBox(width: 8),
              _ReadinessPill(label: 'NFC-e', ready: item.readyForNfce),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  pendingCount == 0
                      ? 'Cadastro fiscal pronto para emissao.'
                      : '$pendingCount pendencia(s) antes de liberar tudo.',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showChecklistDialog(context, item),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Ver checklist'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showChecklistDialog(
    BuildContext context,
    FiscalSetupChecklist checklist,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Checklist fiscal'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: checklist.items
                  .map((entry) => _ChecklistTile(item: entry))
                  .toList(growable: false),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _ReadinessPill extends StatelessWidget {
  const _ReadinessPill({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF047857) : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${ready ? 'pronta' : 'pendente'}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({required this.item});

  final FiscalSetupChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final ok = item.status == 'ok';
    final attention = item.status == 'attention';
    final color = ok
        ? const Color(0xFF047857)
        : attention
            ? const Color(0xFFB45309)
            : const Color(0xFFB91C1C);
    final icon = ok
        ? Icons.check_circle_outline
        : attention
            ? Icons.warning_amber_outlined
            : Icons.error_outline;
    return Container(
      width: 330,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        border: Border.all(color: color.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Responsavel: ${_ownerLabel(item.owner)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ownerLabel(String value) {
    return switch (value) {
      'master' => 'Master/suporte',
      'cliente' => 'Cliente',
      'contador' => 'Contador',
      'suporte' => 'Suporte',
      _ => value,
    };
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.canManage,
    required this.saving,
    required this.onToggleNfce,
    required this.onTogglePdvNfce,
    required this.onToggleNfe,
    required this.onEditCompanyData,
    required this.onSaveCsc,
    required this.onUploadCertificate,
    required this.onDeleteCertificate,
    required this.syncingNfceNumbering,
    required this.onSyncNfceNumbering,
    required this.recoveringFiscalDocuments,
    required this.onRecoverFiscalDocuments,
  });

  final CompanyFiscalSetting? settings;
  final bool canManage;
  final bool saving;
  final ValueChanged<bool> onToggleNfce;
  final ValueChanged<bool> onTogglePdvNfce;
  final ValueChanged<bool> onToggleNfe;
  final VoidCallback onEditCompanyData;
  final VoidCallback onSaveCsc;
  final VoidCallback onUploadCertificate;
  final VoidCallback onDeleteCertificate;
  final bool syncingNfceNumbering;
  final VoidCallback onSyncNfceNumbering;
  final bool recoveringFiscalDocuments;
  final VoidCallback onRecoverFiscalDocuments;

  @override
  Widget build(BuildContext context) {
    final item = settings;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuração fiscal da empresa',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ChipLine('Ambiente', item?.environment ?? 'homologação'),
              _ChipLine(
                'CNPJ',
                item?.cnpj?.isNotEmpty == true ? 'ok' : 'pendente',
              ),
              _ChipLine(
                'IE',
                item?.stateRegistration?.isNotEmpty == true ? 'ok' : 'pendente',
              ),
              _ChipLine(
                'CRT',
                item?.crt?.isNotEmpty == true ? item!.crt! : 'pendente',
              ),
              _ChipLine(
                'UF',
                item?.uf?.isNotEmpty == true ? item!.uf! : 'pendente',
              ),
              _ChipLine(
                'Cidade IBGE',
                item?.cityCode?.isNotEmpty == true
                    ? item!.cityCode!
                    : 'pendente',
              ),
              _ChipLine(
                'NFC-e',
                item?.nfceEnabled == true ? 'habilitada' : 'desabilitada',
              ),
              _ChipLine(
                'Fiscal no PDV',
                item?.pdvNfceEnabled == true ? 'ativo' : 'inativo',
              ),
              _ChipLine(
                'NF-e',
                item?.nfeEnabled == true ? 'habilitada' : 'desabilitada',
              ),
              _ChipLine(
                'Certificado A1',
                item?.hasCertificate == true ? 'cadastrado' : 'pendente',
              ),
              _ChipLine('Série NFC-e', '${item?.nfceSeries ?? 1}'),
              _ChipLine('Proxima NFC-e', '${item?.nfceNextNumber ?? 1}'),
              _ChipLine(
                'CSC NFC-e',
                item?.hasNfceCsc == true ? 'cadastrado' : 'pendente',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (canManage) ...[
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    value: item?.nfceEnabled == true,
                    onChanged: saving ? null : onToggleNfce,
                    title: const Text('Habilitar NFC-e'),
                    subtitle: const Text(
                      'Mantém o modelo 65 disponível no módulo fiscal.',
                    ),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    value: item?.nfeEnabled == true,
                    onChanged: saving ? null : onToggleNfe,
                    title: const Text('Habilitar NF-e'),
                    subtitle: const Text('Modelo 55 para emissão futura.'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: item?.pdvNfceEnabled == true,
              onChanged: saving || item?.nfceEnabled != true
                  ? null
                  : onTogglePdvNfce,
              title: const Text('Emitir NFC-e automaticamente no PDV'),
              subtitle: const Text(
                'Desligado: o caixa vende normalmente sem pedir CPF/CNPJ e sem enviar para a SEFAZ.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onEditCompanyData,
                  icon: const Icon(Icons.business_outlined),
                  label: const Text('Dados fiscais'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : onUploadCertificate,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    item?.hasCertificate == true
                        ? 'Trocar certificado A1'
                        : 'Cadastrar certificado A1',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: saving || item?.hasCertificate != true
                      ? null
                      : onDeleteCertificate,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover certificado'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : onSaveCsc,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(
                    item?.hasNfceCsc == true
                        ? 'Trocar CSC / ID'
                        : 'Cadastrar CSC / ID',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      saving ||
                          syncingNfceNumbering ||
                          item?.environment != 'homologacao' ||
                          item?.hasCertificate != true
                      ? null
                      : onSyncNfceNumbering,
                  icon: syncingNfceNumbering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Sincronizar com a SEFAZ'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      saving ||
                          recoveringFiscalDocuments ||
                          item?.environment != 'homologacao' ||
                          item?.hasCertificate != true
                      ? null
                      : onRecoverFiscalDocuments,
                  icon: recoveringFiscalDocuments
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Recuperar notas da SEFAZ'),
                ),
              ],
            ),
            if (item?.certificateFileSha256 != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                'SHA-256: ${item!.certificateFileSha256}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
          ],
          const Text(
            'O certificado A1 fica criptografado no banco separado desta empresa. Assinatura XML e comunicação SEFAZ entram na homologação fiscal real.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _RtcCompliancePanel extends StatelessWidget {
  const _RtcCompliancePanel({required this.compliance});

  final RtcCompliance? compliance;

  @override
  Widget build(BuildContext context) {
    final item = compliance;
    if (item == null) {
      return const AppCard(
        child: Text(
          'A verificação da Reforma Tributária será exibida após carregar os dados fiscais.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final needsAction = item.mandatory && !item.ready;
    final statusColor = needsAction
        ? const Color(0xFFB42318)
        : item.mandatory
        ? const Color(0xFF157347)
        : const Color(0xFF075985);
    final statusBackground = needsAction
        ? const Color(0xFFFFF1F0)
        : item.mandatory
        ? const Color(0xFFECFDF3)
        : const Color(0xFFEFF8FF);
    final statusText = needsAction
        ? 'Ação necessária'
        : item.mandatory
        ? 'Pronto para emissão'
        : 'Cronograma preservado';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  needsAction
                      ? Icons.warning_amber_rounded
                      : Icons.verified_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reforma Tributária 2026',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: .25)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RtcInfoChip(label: 'CRT ${item.effectiveCrt}'),
              _RtcInfoChip(label: 'Modelo ${item.documentModel}'),
              _RtcInfoChip(
                label: item.mandatory
                    ? 'Obrigatório desde 03/08/2026'
                    : 'Sem exigência imediata',
              ),
              if (item.cbsRate != null)
                _RtcInfoChip(label: 'CBS ${_rateLabel(item.cbsRate!)}'),
              if (item.ibsStateRate != null)
                _RtcInfoChip(label: 'IBS UF ${_rateLabel(item.ibsStateRate!)}'),
              if (item.ibsCityRate != null)
                _RtcInfoChip(
                  label: 'IBS Município ${_rateLabel(item.ibsCityRate!)}',
                ),
            ],
          ),
          if (!item.mandatory) ...[
            const SizedBox(height: 14),
            const Text(
              'Nenhum campo novo será exigido deste emitente agora. As regras atuais de MEI e Simples Nacional permanecem preservadas.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (needsAction) ...[
            const SizedBox(height: 16),
            Text(
              '${item.productsIncomplete} de ${item.productsTotal} produto(s) precisam de revisão antes da emissão.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...item.incompleteProducts
                .take(8)
                .map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: product.internalCode?.isNotEmpty == true
                                      ? '${product.internalCode} - ${product.name}: '
                                      : '${product.name}: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: product.missingFields.join(', '),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (item.incompleteProducts.length > 8)
              Text(
                'E mais ${item.incompleteProducts.length - 8} produto(s).',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
          ],
        ],
      ),
    );
  }

  static String _rateLabel(double value) {
    return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}%';
  }
}

class _RtcInfoChip extends StatelessWidget {
  const _RtcInfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _FiscalOutputRulesCard extends StatelessWidget {
  const _FiscalOutputRulesCard({
    required this.rules,
    required this.canManage,
    required this.saving,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<FiscalOutputRule> rules;
  final bool canManage;
  final bool saving;
  final VoidCallback onCreate;
  final ValueChanged<FiscalOutputRule> onEdit;
  final ValueChanged<FiscalOutputRule> onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
                      'Regras fiscais de saída',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Define como NFC-e/NF-e devem sair por regime, modelo, NCM/CEST ou produto. Nao altera XML de entrada.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: saving ? null : onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Nova regra'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'As regras sao sugestoes/configuracoes fiscais e devem ser conferidas pelo contador ou responsavel fiscal.',
            style: TextStyle(
              color: Color(0xFFB45309),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nenhuma regra cadastrada. O motor usa o padrao seguro por regime/CRT e os dados do produto.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          else
            ...rules.map(
              (rule) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: rule.active
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      rule.active
                          ? Icons.rule_folder_outlined
                          : Icons.block_outlined,
                      color: rule.active
                          ? const Color(0xFF0F766E)
                          : const Color(0xFFB91C1C),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              'Prioridade ${rule.priority}',
                              rule.documentModel == null
                                  ? 'NF-e/NFC-e'
                                  : 'Modelo ${rule.documentModel}',
                              if (rule.crt != null) 'CRT ${rule.crt}',
                              if (rule.ncm != null) 'NCM ${rule.ncm}',
                              if (rule.ncmPrefix != null)
                                'NCM inicia ${rule.ncmPrefix}',
                              if (rule.cest != null) 'CEST ${rule.cest}',
                              if (rule.productName != null)
                                'Produto ${rule.productName}',
                              if (rule.cfop != null) 'CFOP ${rule.cfop}',
                              if (rule.csosn != null) 'CSOSN ${rule.csosn}',
                              if (rule.cst != null) 'CST ${rule.cst}',
                            ].join(' • '),
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    if (canManage) ...[
                      IconButton(
                        tooltip: 'Editar regra',
                        onPressed: saving ? null : () => onEdit(rule),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Excluir regra',
                        onPressed: saving ? null : () => onDelete(rule),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FiscalOutputRuleDialog extends StatefulWidget {
  const _FiscalOutputRuleDialog({required this.rule, required this.settings});

  final FiscalOutputRule? rule;
  final CompanyFiscalSetting? settings;

  @override
  State<_FiscalOutputRuleDialog> createState() =>
      _FiscalOutputRuleDialogState();
}

class _FiscalOutputRuleDialogState extends State<_FiscalOutputRuleDialog> {
  late final TextEditingController _name = TextEditingController(
    text:
        widget.rule?.name ??
        'Venda padrao ${widget.settings?.crt == '4' ? 'MEI' : ''}'.trim(),
  );
  late final TextEditingController _priority = TextEditingController(
    text: '${widget.rule?.priority ?? 100}',
  );
  late final TextEditingController _ncm = TextEditingController(
    text: widget.rule?.ncm ?? '',
  );
  late final TextEditingController _ncmPrefix = TextEditingController(
    text: widget.rule?.ncmPrefix ?? '',
  );
  late final TextEditingController _cest = TextEditingController(
    text: widget.rule?.cest ?? '',
  );
  late final TextEditingController _productId = TextEditingController(
    text: widget.rule?.productId?.toString() ?? '',
  );
  late final TextEditingController _cfop = TextEditingController(
    text: widget.rule?.cfop ?? '5102',
  );
  late final TextEditingController _origin = TextEditingController(
    text: widget.rule?.origin ?? '0',
  );
  late final TextEditingController _cst = TextEditingController(
    text: widget.rule?.cst ?? '',
  );
  late final TextEditingController _csosn = TextEditingController(
    text: widget.rule?.csosn ?? (widget.settings?.crt == '4' ? '102' : ''),
  );
  late final TextEditingController _pisCst = TextEditingController(
    text: widget.rule?.pisCst ?? '07',
  );
  late final TextEditingController _cofinsCst = TextEditingController(
    text: widget.rule?.cofinsCst ?? '07',
  );
  late final TextEditingController _ibsCbsCst = TextEditingController(
    text: widget.rule?.ibsCbsCst ?? '',
  );
  late final TextEditingController _ibsCbsClass = TextEditingController(
    text: widget.rule?.ibsCbsClassification ?? '',
  );
  late final TextEditingController _cbsRate = TextEditingController(
    text: widget.rule?.cbsRate?.toString() ?? '',
  );
  late final TextEditingController _ibsUfRate = TextEditingController(
    text: widget.rule?.ibsStateRate?.toString() ?? '',
  );
  late final TextEditingController _ibsMunRate = TextEditingController(
    text: widget.rule?.ibsCityRate?.toString() ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.rule?.notes ?? '',
  );
  late bool _active = widget.rule?.active ?? true;
  late String? _model = widget.rule?.documentModel ?? '65';
  late String? _crt = widget.rule?.crt ?? widget.settings?.crt;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _priority,
      _ncm,
      _ncmPrefix,
      _cest,
      _productId,
      _cfop,
      _origin,
      _cst,
      _csosn,
      _pisCst,
      _cofinsCst,
      _ibsCbsCst,
      _ibsCbsClass,
      _cbsRate,
      _ibsUfRate,
      _ibsMunRate,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.rule == null
            ? 'Nova regra fiscal de saída'
            : 'Editar regra fiscal de saída',
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Regra ativa'),
              ),
              _field(_name, 'Nome da regra'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_priority, 'Prioridade')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _model,
                      decoration: const InputDecoration(
                        labelText: 'Modelo',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('NF-e e NFC-e'),
                        ),
                        DropdownMenuItem(
                          value: '65',
                          child: Text('NFC-e modelo 65'),
                        ),
                        DropdownMenuItem(
                          value: '55',
                          child: Text('NF-e modelo 55'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _model = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _crt,
                      decoration: const InputDecoration(
                        labelText: 'CRT',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Qualquer CRT'),
                        ),
                        DropdownMenuItem(
                          value: '1',
                          child: Text('1 - Simples Nacional'),
                        ),
                        DropdownMenuItem(
                          value: '2',
                          child: Text('2 - Excesso sublimite'),
                        ),
                        DropdownMenuItem(
                          value: '3',
                          child: Text('3 - Regime normal'),
                        ),
                        DropdownMenuItem(value: '4', child: Text('4 - MEI')),
                      ],
                      onChanged: (value) => setState(() => _crt = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_ncm, 'NCM exato')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_ncmPrefix, 'Prefixo NCM')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_cest, 'CEST')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(_productId, 'ID do produto especifico'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_cfop, 'CFOP saída')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_origin, 'Origem')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_csosn, 'CSOSN')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_cst, 'CST ICMS')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_pisCst, 'PIS CST')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_cofinsCst, 'COFINS CST')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_ibsCbsCst, 'IBS/CBS CST')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_ibsCbsClass, 'cClassTrib IBS/CBS')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_cbsRate, 'CBS %')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_ibsUfRate, 'IBS UF %')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_ibsMunRate, 'IBS Mun %')),
                ],
              ),
              const SizedBox(height: 10),
              _field(_notes, 'Observacoes da regra', maxLines: 3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Salvar regra')),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  double? _num(TextEditingController controller) {
    final value = controller.text.trim().replaceAll(',', '.');
    return value.isEmpty ? null : double.tryParse(value);
  }

  void _submit() {
    final name = _text(_name);
    if (name == null) return;
    Navigator.pop(context, {
      'name': name,
      'active': _active,
      'priority': int.tryParse(_priority.text.trim()) ?? 100,
      'operation_type': 'sale',
      'document_model': _model,
      'crt': _crt,
      'ncm': _text(_ncm),
      'ncm_prefix': _text(_ncmPrefix),
      'cest': _text(_cest),
      'product_id': int.tryParse(_productId.text.trim()),
      'cfop': _text(_cfop),
      'origin': _text(_origin),
      'cst': _text(_cst),
      'csosn': _text(_csosn),
      'pis_cst': _text(_pisCst),
      'cofins_cst': _text(_cofinsCst),
      'ibs_cbs_cst': _text(_ibsCbsCst),
      'ibs_cbs_classification': _text(_ibsCbsClass),
      'cbs_rate': _num(_cbsRate),
      'ibs_state_rate': _num(_ibsUfRate),
      'ibs_city_rate': _num(_ibsMunRate),
      'notes': _text(_notes),
    });
  }
}

class _ChipLine extends StatelessWidget {
  const _ChipLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: const Color(0xFFEFF6FF),
      side: const BorderSide(color: Color(0xFFBFDBFE)),
    );
  }
}

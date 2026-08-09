import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/company.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/support_file_actions.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MasterContractsScreen extends StatefulWidget {
  const MasterContractsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterContractsScreen> createState() => _MasterContractsScreenState();
}

class _MasterContractsScreenState extends State<MasterContractsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<CompanyContract> _contracts = [];
  String _filter = 'todos';
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
      final contracts = await _api.listCompanyContracts(widget.session.token);
      setState(() => _contracts = contracts);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CompanyContract> get _filtered {
    if (_filter == 'todos') return _contracts;
    return _contracts.where((item) => item.attentionLevel == _filter).toList();
  }

  Future<void> _openContract(CompanyContract contract) async {
    final companies = await _api.listCompanies(widget.session.token);
    final company = companies.firstWhere((item) => item.id == contract.id);
    if (!mounted) return;
    final updated = await showDialog<CompanyInput>(
      context: context,
      builder: (context) =>
          _ContractDialog(session: widget.session, api: _api, company: company),
    );
    if (updated == null) return;
    await _api.updateCompany(widget.session.token, company.id, updated);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final expiring = _contracts
        .where((item) => item.attentionLevel == 'atencao_master')
        .length;
    final expired = _contracts
        .where((item) => item.attentionLevel == 'vencido')
        .length;
    final missing = _contracts
        .where((item) => item.attentionLevel == 'sem_contrato')
        .length;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contratos',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF142033),
                          ),
                    ),
                    const Gap(6),
                    const Text(
                      'Controle contratos anuais, anexos e vencimentos dos clientes.',
                      style: TextStyle(color: Color(0xFF60708A), fontSize: 16),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Gap(20),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Vencendo em 40 dias',
                  value: '$expiring',
                ),
              ),
              const Gap(12),
              Expanded(
                child: _Metric(label: 'Vencidos', value: '$expired'),
              ),
              const Gap(12),
              Expanded(
                child: _Metric(label: 'Sem contrato', value: '$missing'),
              ),
            ],
          ),
          const Gap(16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'todos', label: Text('Todos')),
              ButtonSegment(value: 'atencao_master', label: Text('Vencendo')),
              ButtonSegment(value: 'vencido', label: Text('Vencidos')),
              ButtonSegment(value: 'sem_contrato', label: Text('Sem contrato')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
          ),
          const Gap(16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorPanel(message: _error!, onRetry: _load)
                : AppCard(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final contract = _filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(
                              contract,
                            ).withValues(alpha: 0.10),
                            child: Icon(
                              Icons.description_outlined,
                              color: _statusColor(contract),
                            ),
                          ),
                          title: Text(
                            contract.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${contract.code} • ${_subtitle(contract)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusChip(contract: contract),
                              if (contract.contractFileUrl?.isNotEmpty == true)
                                IconButton.outlined(
                                  tooltip: 'Abrir contrato',
                                  onPressed: () => _openContractFile(
                                    context,
                                    widget.session.apiBaseUrl,
                                    contract.contractFileUrl!,
                                  ),
                                  icon: const Icon(Icons.open_in_new),
                                ),
                              if (contract.contractFileUrl?.isNotEmpty == true)
                                IconButton.outlined(
                                  tooltip: 'Baixar contrato',
                                  onPressed: () => _downloadContractFile(
                                    context,
                                    widget.session.apiBaseUrl,
                                    contract.contractFileUrl!,
                                    contract.contractFileName ?? 'contrato',
                                  ),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                              OutlinedButton.icon(
                                onPressed: () => _openContract(contract),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                label: const Text('Editar'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitle(CompanyContract contract) {
    final signed = _formatDate(contract.contractSignedAt);
    final expires = _formatDate(contract.contractExpiresAt);
    final file = contract.contractFileName ?? 'sem anexo';
    if (expires == '-') return 'sem data de vencimento • $file';
    return 'assinado em $signed • vence em $expires • $file';
  }

  Color _statusColor(CompanyContract contract) {
    return switch (contract.attentionLevel) {
      'vencido' => const Color(0xFFB42318),
      'atencao_master' => const Color(0xFFC2410C),
      'ativo' => const Color(0xFF15803D),
      _ => const Color(0xFF60708A),
    };
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.event_available_outlined, color: Color(0xFF146B83)),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF60708A))),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.contract});

  final CompanyContract contract;

  @override
  Widget build(BuildContext context) {
    final label = switch (contract.attentionLevel) {
      'vencido' => 'Vencido',
      'atencao_master' => 'Vencendo',
      'ativo' => 'Ativo',
      _ => 'Sem contrato',
    };
    final color = switch (contract.attentionLevel) {
      'vencido' => const Color(0xFFB42318),
      'atencao_master' => const Color(0xFFC2410C),
      'ativo' => const Color(0xFF15803D),
      _ => const Color(0xFF60708A),
    };
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.18)),
    );
  }
}

class _ContractDialog extends StatefulWidget {
  const _ContractDialog({
    required this.session,
    required this.api,
    required this.company,
  });

  final Session session;
  final ApiClient api;
  final Company company;

  @override
  State<_ContractDialog> createState() => _ContractDialogState();
}

class _ContractDialogState extends State<_ContractDialog> {
  final _signed = TextEditingController();
  final _expires = TextEditingController();
  final _notes = TextEditingController();
  String? _fileUrl;
  String? _fileName;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _signed.text = widget.company.contractSignedAt ?? '';
    _expires.text = widget.company.contractExpiresAt ?? '';
    _notes.text = widget.company.contractNotes ?? '';
    _fileUrl = widget.company.contractFileUrl;
    _fileName = widget.company.contractFileName;
  }

  @override
  void dispose() {
    _signed.dispose();
    _expires.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickContract() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() => _uploading = true);
    try {
      final upload = await widget.api.uploadContract(
        widget.session.token,
        bytes: bytes,
        filename: file.name,
      );
      setState(() {
        _fileUrl = upload['url'];
        _fileName = upload['name'] ?? file.name;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Contrato - ${widget.company.name}'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _signed,
                    decoration: const InputDecoration(
                      labelText: 'Data de assinatura',
                      helperText: 'DD/MM/AAAA ou AAAA-MM-DD',
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: _expires,
                    decoration: const InputDecoration(
                      labelText: 'Vencimento',
                      helperText: 'Opcional; vazio calcula 12 meses',
                    ),
                  ),
                ),
              ],
            ),
            const Gap(14),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const Gap(14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName == null
                        ? 'Nenhum contrato anexado.'
                        : 'Anexo: $_fileName',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _pickContract,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                  label: const Text('Anexar'),
                ),
                if (_fileUrl?.isNotEmpty == true) ...[
                  const Gap(8),
                  IconButton.outlined(
                    tooltip: 'Abrir contrato',
                    onPressed: () => _openContractFile(
                      context,
                      widget.session.apiBaseUrl,
                      _fileUrl!,
                    ),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  const Gap(8),
                  IconButton.outlined(
                    tooltip: 'Baixar contrato',
                    onPressed: () => _downloadContractFile(
                      context,
                      widget.session.apiBaseUrl,
                      _fileUrl!,
                      _fileName ?? 'contrato',
                    ),
                    icon: const Icon(Icons.download_outlined),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              _inputFromCompany(
                widget.company,
                contractSignedAt: _dateInputToIsoOrRaw(_signed.text),
                contractExpiresAt: _dateInputToIsoOrRaw(_expires.text),
                contractFileUrl: _fileUrl,
                contractFileName: _fileName,
                contractNotes: _emptyToNull(_notes.text),
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar contrato'),
        ),
      ],
    );
  }
}

Uri _contractFileUri(String apiBaseUrl, String url) {
  final parsed = Uri.parse(url);
  if (parsed.hasScheme) return parsed;
  final normalizedBase = apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/';
  return Uri.parse(normalizedBase).resolve(url);
}

Future<void> _openContractFile(
  BuildContext context,
  String apiBaseUrl,
  String url,
) async {
  try {
    final opened = await launchUrl(
      _contractFileUri(apiBaseUrl, url),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o contrato.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível abrir o contrato: $error')),
    );
  }
}

Future<void> _downloadContractFile(
  BuildContext context,
  String apiBaseUrl,
  String url,
  String filename,
) async {
  try {
    await downloadSupportFile(_contractFileUri(apiBaseUrl, url), filename);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível baixar o contrato: $error')),
    );
  }
}

CompanyInput _inputFromCompany(
  Company company, {
  String? contractSignedAt,
  String? contractExpiresAt,
  String? contractFileUrl,
  String? contractFileName,
  String? contractNotes,
}) {
  return CompanyInput(
    code: company.code,
    name: company.name,
    businessType: company.businessType,
    personType: company.personType,
    documentNumber: company.documentNumber,
    stateRegistration: company.stateRegistration,
    tradeName: company.tradeName,
    contactName: company.contactName,
    phone: company.phone,
    email: company.email,
    addressLine: company.addressLine,
    addressNumber: company.addressNumber,
    neighborhood: company.neighborhood,
    city: company.city,
    cityCode: company.cityCode,
    state: company.state,
    zipCode: company.zipCode,
    taxRegime: company.taxRegime,
    crt: company.crt,
    databaseUrl: company.databaseUrl,
    plan: company.plan,
    planOverrides: company.planOverrides,
    enabledModules: company.enabledModules,
    monthlyPrice: company.monthlyPrice,
    billingDay: company.billingDay,
    paymentMethod: company.paymentMethod,
    contractSignedAt: contractSignedAt,
    contractExpiresAt: contractExpiresAt,
    contractFileUrl: contractFileUrl,
    contractFileName: contractFileName,
    contractNotes: contractNotes,
    digitalCertificateConfigured: company.digitalCertificateConfigured,
    digitalCertificateName: company.digitalCertificateName,
    digitalCertificateExpiresAt: company.digitalCertificateExpiresAt,
    digitalCertificateNotes: company.digitalCertificateNotes,
    status: company.status,
    active: company.active,
    provisionDatabase: false,
    adminName: 'admin',
    adminEmail: company.email ?? 'admin@local.test',
    adminPassword: 'nao-usado',
    notes: company.notes,
  );
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _dateInputToIsoOrRaw(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final slashParts = trimmed.split('/');
  if (slashParts.length == 3) {
    final day = slashParts[0].padLeft(2, '0');
    final month = slashParts[1].padLeft(2, '0');
    final year = slashParts[2];
    if (year.length == 4) {
      return '$year-$month-$day';
    }
  }
  return trimmed;
}

String _formatDate(String? value) {
  if (value == null || value.isEmpty) return '-';
  final parts = value.split('-');
  if (parts.length != 3) return value;
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

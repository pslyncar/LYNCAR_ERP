import 'package:flutter/material.dart';
import '../models/session.dart';
import '../models/master_finance_setting.dart';
import '../services/api_client.dart';

class MasterFinanceSettingsScreen extends StatefulWidget {
  const MasterFinanceSettingsScreen({super.key, required this.session});
  final Session session;
  @override
  State<MasterFinanceSettingsScreen> createState() => _State();
}

class _State extends State<MasterFinanceSettingsScreen> {
  late final api = ApiClient(widget.session.apiBaseUrl);
  final fee = TextEditingController(),
      interest = TextEditingController(),
      grace = TextEditingController();
  bool enabled = false, loading = true, saving = false;
  bool monetaryEnabled = true, automaticIndex = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await api.getMasterFinanceSetting(widget.session.token);
      setState(() {
        enabled = s.enabled;
        fee.text = s.feePercent.toString();
        interest.text = s.dailyInterestPercent.toString();
        grace.text = s.graceDays.toString();
        loading = false;
        monetaryEnabled = s.monetaryCorrectionEnabled;
        automaticIndex = s.automaticIndexUpdate;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await api.updateMasterFinanceSetting(
        widget.session.token,
        MasterFinanceSetting(
          enabled: enabled,
          feePercent: double.tryParse(fee.text.replaceAll(',', '.')) ?? 0,
          dailyInterestPercent:
              double.tryParse(interest.text.replaceAll(',', '.')) ?? 0,
          graceDays: int.tryParse(grace.text) ?? 0,
          monetaryCorrectionEnabled: monetaryEnabled,
          monetaryIndex: 'IPCA',
          automaticIndexUpdate: automaticIndex,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Política financeira salva.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Financeiro', style: Theme.of(c).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Política geral de cobrança do Master'),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Aplicar encargos por atraso'),
                    subtitle: const Text(
                      'Usada como padrão para novas mensalidades de todas as empresas.',
                    ),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fee,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Multa (%)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: interest,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Juros ao mês (%)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: grace,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Carência (dias)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Correção monetária pelo IPCA'),
                    subtitle: const Text(
                      'Índice oficial do IBGE, atualizado automaticamente.',
                    ),
                    value: monetaryEnabled,
                    onChanged: (v) => setState(() => monetaryEnabled = v),
                  ),
                  SwitchListTile(
                    title: const Text('Atualizar índices automaticamente'),
                    subtitle: const Text(
                      'O sistema consulta o IBGE sem cadastro manual e não duplica competências.',
                    ),
                    value: automaticIndex,
                    onChanged: monetaryEnabled
                        ? (v) => setState(() => automaticIndex = v)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'A política é aplicada no vencimento e os valores ficam registrados na cobrança. Alterações não reescrevem mensalidades já geradas. O perdão continua sendo feito individualmente quando necessário.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(saving ? 'Salvando…' : 'Salvar política'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

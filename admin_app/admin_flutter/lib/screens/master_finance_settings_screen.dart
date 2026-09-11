import 'package:flutter/material.dart';

import '../models/master_finance_setting.dart';
import '../models/session.dart';
import '../models/subscription_plan.dart';
import '../services/api_client.dart';

class MasterFinanceSettingsScreen extends StatefulWidget {
  const MasterFinanceSettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterFinanceSettingsScreen> createState() => _State();
}

class _State extends State<MasterFinanceSettingsScreen> {
  late final api = ApiClient(widget.session.apiBaseUrl);
  final fee = TextEditingController();
  final interest = TextEditingController();
  final grace = TextEditingController();
  bool enabled = false, loading = true, saving = false;
  bool monetaryEnabled = true, automaticIndex = true;
  String? planError;
  List<SubscriptionPlan> plans = const [];
  final Map<String, bool> planEnabled = {};
  final Map<String, TextEditingController> planFee = {};
  final Map<String, TextEditingController> planInterest = {};
  final Map<String, TextEditingController> planGrace = {};
  final Set<String> savingPlans = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    fee.dispose();
    interest.dispose();
    grace.dispose();
    for (final controller in [
      ...planFee.values,
      ...planInterest.values,
      ...planGrace.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.getMasterFinanceSetting(widget.session.token),
        api.listMasterPlans(widget.session.token),
      ]);
      final setting = results[0] as MasterFinanceSetting;
      final loadedPlans = results[1] as List<SubscriptionPlan>;
      if (!mounted) return;
      _preparePlanControllers(loadedPlans);
      setState(() {
        enabled = setting.enabled;
        fee.text = setting.feePercent.toString();
        interest.text = setting.dailyInterestPercent.toString();
        grace.text = setting.graceDays.toString();
        monetaryEnabled = setting.monetaryCorrectionEnabled;
        automaticIndex = setting.automaticIndexUpdate;
        plans = loadedPlans.where((plan) => plan.active).toList();
        planError = null;
        loading = false;
      });
    } catch (_) {
      try {
        final setting = await api.getMasterFinanceSetting(widget.session.token);
        if (!mounted) return;
        setState(() {
          enabled = setting.enabled;
          fee.text = setting.feePercent.toString();
          interest.text = setting.dailyInterestPercent.toString();
          grace.text = setting.graceDays.toString();
          monetaryEnabled = setting.monetaryCorrectionEnabled;
          automaticIndex = setting.automaticIndexUpdate;
          planError = 'Não foi possível carregar as políticas dos planos.';
          loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => loading = false);
      }
    }
  }

  void _preparePlanControllers(List<SubscriptionPlan> loadedPlans) {
    for (final plan in loadedPlans) {
      planEnabled[plan.code] = plan.lateChargesEnabled;
      planFee[plan.code] ??= TextEditingController(
        text: _number(plan.lateFeePercent),
      );
      planInterest[plan.code] ??= TextEditingController(
        text: _number(plan.lateInterestDailyPercent),
      );
      planGrace[plan.code] ??= TextEditingController(
        text: plan.lateGraceDays.toString(),
      );
    }
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  double _parseDouble(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await api.updateMasterFinanceSetting(
        widget.session.token,
        MasterFinanceSetting(
          enabled: enabled,
          feePercent: _parseDouble(fee.text),
          dailyInterestPercent: _parseDouble(interest.text),
          graceDays: int.tryParse(grace.text) ?? 0,
          monetaryCorrectionEnabled: monetaryEnabled,
          monetaryIndex: 'IPCA',
          automaticIndexUpdate: automaticIndex,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Política geral salva.')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _savePlan(SubscriptionPlan plan) async {
    setState(() => savingPlans.add(plan.code));
    try {
      final updated = SubscriptionPlan(
        id: plan.id,
        code: plan.code,
        name: plan.name,
        monthlyPrice: plan.monthlyPrice,
        annualPrice: plan.annualPrice,
        maxUsers: plan.maxUsers,
        maxPdvTerminals: plan.maxPdvTerminals,
        databaseLimitMb: plan.databaseLimitMb,
        fileLimitMb: plan.fileLimitMb,
        multiCompanyLimit: plan.multiCompanyLimit,
        marketplaceListingLimit: plan.marketplaceListingLimit,
        apiEnabled: plan.apiEnabled,
        prioritySupport: plan.prioritySupport,
        lateChargesEnabled: planEnabled[plan.code] ?? false,
        lateFeePercent: _parseDouble(planFee[plan.code]!.text),
        lateInterestDailyPercent: _parseDouble(planInterest[plan.code]!.text),
        lateGraceDays: int.tryParse(planGrace[plan.code]!.text) ?? 0,
        defaultModules: plan.defaultModules,
        active: plan.active,
        sortOrder: plan.sortOrder,
      );
      final saved = await api.updateMasterPlan(
        widget.session.token,
        plan.code,
        updated,
      );
      if (!mounted) return;
      setState(() {
        plans = plans
            .map((item) => item.code == saved.code ? saved : item)
            .toList();
        planEnabled[saved.code] = saved.lateChargesEnabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Política do plano ${plan.name} salva.')),
      );
    } finally {
      if (mounted) setState(() => savingPlans.remove(plan.code));
    }
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  );

  Widget _planCard(SubscriptionPlan plan) {
    final isSaving = savingPlans.contains(plan.code);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        leading: const CircleAvatar(child: Icon(Icons.workspace_premium)),
        title: Text(plan.name),
        subtitle: Text(
          plan.lateChargesEnabled
              ? 'Encargos ativos • ${plan.lateGraceDays} dias de carência'
              : 'Sem encargos por atraso',
        ),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aplicar encargos neste plano'),
            subtitle: const Text(
              'Define se as novas cobranças deste plano terão multa e juros.',
            ),
            value: planEnabled[plan.code] ?? false,
            onChanged: isSaving
                ? null
                : (value) => setState(() => planEnabled[plan.code] = value),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _field(planFee[plan.code]!, 'Multa (%)'),
                _field(planInterest[plan.code]!, 'Juros ao dia (%)'),
                _field(planGrace[plan.code]!, 'Carência (dias)'),
              ];
              if (constraints.maxWidth < 720) {
                return Column(
                  children: fields
                      .map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: field,
                        ),
                      )
                      .toList(),
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: fields[i]),
                  ],
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSaving ? null : () => _savePlan(plan),
              icon: const Icon(Icons.save),
              label: Text(isSaving ? 'Salvando…' : 'Salvar plano'),
            ),
          ),
        ],
      ),
    );
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
          const Text('Políticas de cobrança do Master e dos planos'),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Aplicar encargos por atraso'),
                    subtitle: const Text(
                      'Usada como fallback para novas mensalidades sem política específica do plano.',
                    ),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                  const Divider(),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = [
                        _field(fee, 'Multa (%)'),
                        _field(interest, 'Juros ao dia (%)'),
                        _field(grace, 'Carência (dias)'),
                      ];
                      if (constraints.maxWidth < 720) {
                        return Column(
                          children: fields
                              .map(
                                (field) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: field,
                                ),
                              )
                              .toList(),
                        );
                      }
                      return Row(
                        children: [
                          for (var i = 0; i < fields.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(child: fields[i]),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
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
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'A política geral é aplicada somente como fallback. A regra do plano ativo tem prioridade e alterações não reescrevem mensalidades já geradas.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(
                        saving ? 'Salvando…' : 'Salvar política geral',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Política por plano', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Configure quais planos têm carência, multa e juros. A regra vale para novas mensalidades do plano; cobranças já geradas permanecem com os valores registrados.',
          ),
          const SizedBox(height: 16),
          if (planError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(planError!)),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          else if (plans.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nenhum plano ativo encontrado.'),
              ),
            )
          else
            ...plans.map(_planCard),
        ],
      ),
    );
  }
}

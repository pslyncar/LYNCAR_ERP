import 'package:flutter/material.dart';

import '../models/plan_change.dart';

class PlanChangeSelection {
  const PlanChangeSelection({required this.userIds, required this.terminalIds});

  final List<int> userIds;
  final List<int> terminalIds;
}

class PlanChangePreviewDialog extends StatefulWidget {
  const PlanChangePreviewDialog({super.key, required this.preview});

  final PlanChangePreview preview;

  @override
  State<PlanChangePreviewDialog> createState() =>
      _PlanChangePreviewDialogState();
}

class _PlanChangePreviewDialogState extends State<PlanChangePreviewDialog> {
  final Set<int> _users = <int>{};
  final Set<int> _terminals = <int>{};

  PlanChangePreview get _preview => widget.preview;

  bool get _complete =>
      _users.length >= _preview.requiredUserSelections &&
      _terminals.length >= _preview.requiredTerminalSelections;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Revisar mudança de plano'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${preview.companyCode}: ${preview.currentPlan.toUpperCase()} → ${preview.targetPlan.toUpperCase()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (preview.removedModules.isNotEmpty)
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  title: 'Recursos que deixarão de estar disponíveis',
                  body: preview.removedModules.map(_moduleLabel).join(', '),
                ),
              if (preview.targetPlan.toLowerCase() == 'start')
                const _Notice(
                  icon: Icons.point_of_sale_outlined,
                  color: Colors.blue,
                  title: 'PDV Web no Start',
                  body:
                      'O PDV Web continua disponível com funções básicas e cada funcionário mantém seu próprio login. O PDV Windows não faz parte deste plano.',
                ),
              if (preview.requiredUserSelections > 0) ...[
                const SizedBox(height: 16),
                _sectionTitle(
                  context,
                  'Escolha usuários para inativar',
                  'Limite do novo plano: ${preview.maxUsers ?? 'sem limite'} · ativos: ${preview.activeUsers}',
                ),
                ...preview.users.map((item) => _checkItem(item, _users)),
              ],
              if (preview.requiredTerminalSelections > 0) ...[
                const SizedBox(height: 16),
                _sectionTitle(
                  context,
                  preview.pdvWindowsWillBeRevoked
                      ? 'Terminais PDV Windows que serão revogados'
                      : 'Escolha terminais para inativar',
                  preview.pdvWindowsWillBeRevoked
                      ? 'O novo plano não inclui PDV Windows. Os códigos serão cancelados, sem apagar vendas ou histórico.'
                      : 'Limite do novo plano: ${preview.maxPdvTerminals ?? 'sem limite'} · ativos: ${preview.activeTerminals}',
                ),
                ...preview.terminals.map(
                  (item) => _checkItem(item, _terminals),
                ),
              ],
              if (!_hasSelectionsToMake) ...[
                const SizedBox(height: 16),
                const _Notice(
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  title: 'Nenhum recurso precisa ser inativado',
                  body: 'A alteração pode ser aplicada imediatamente.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _complete ? _apply : null,
          child: const Text('Aplicar mudança'),
        ),
      ],
    );
  }

  bool get _hasSelectionsToMake =>
      _preview.requiredUserSelections > 0 ||
      _preview.requiredTerminalSelections > 0;

  Widget _checkItem(PlanChangeItem item, Set<int> selected) {
    final checked = selected.contains(item.id);
    return CheckboxListTile(
      dense: true,
      value: checked,
      title: Text(item.label),
      subtitle: item.detail == null ? null : Text(item.detail!),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) => setState(() {
        if (value == true) {
          selected.add(item.id);
        } else {
          selected.remove(item.id);
        }
      }),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  void _apply() {
    Navigator.of(context).pop(
      PlanChangeSelection(
        userIds: _users.toList(),
        terminalIds: _terminals.toList(),
      ),
    );
  }

  String _moduleLabel(String value) {
    const labels = <String, String>{
      'pdv': 'PDV Web',
      'pdv_windows': 'PDV Windows',
      'stock': 'Estoque',
      'fiscal': 'Fiscal',
      'finance': 'Financeiro',
      'customers': 'Clientes',
      'suppliers': 'Fornecedores',
      'reports': 'Relatórios',
    };
    return labels[value] ?? value;
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
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
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

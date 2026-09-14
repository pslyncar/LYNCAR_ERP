import 'package:flutter/material.dart';

import '../models/pdv_operator.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class PdvOperatorsScreen extends StatefulWidget {
  const PdvOperatorsScreen({
    super.key,
    required this.session,
    this.waitersOnly = false,
    this.pedeonOnly = false,
  });

  final Session session;
  final bool waitersOnly;
  final bool pedeonOnly;

  @override
  State<PdvOperatorsScreen> createState() => _PdvOperatorsScreenState();
}

class _PdvOperatorsScreenState extends State<PdvOperatorsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<PdvOperator> _operators = [];
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
      final operators = await _api.listPdvOperators(
        widget.session.token,
        activeOnly: false,
      );
      setState(
        () => _operators = operators
            .where(
              (item) => widget.waitersOnly
                  ? item.role == 'waiter'
                  : widget.pedeonOnly
                  ? item.role == 'pedeon_operator'
                  : item.role != 'waiter' && item.role != 'pedeon_operator',
            )
            .toList(),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar operadores.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([PdvOperator? operator]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _OperatorDialog(
        api: _api,
        token: widget.session.token,
        operator: operator,
        waiterOnly: widget.waitersOnly,
        pedeonOnly: widget.pedeonOnly,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteOperator(PdvOperator operator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir operador?'),
        content: Text(
          'Deseja realmente excluir o operador "${operator.name}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deletePdvOperator(widget.session.token, operator.id);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pedeonOnly ? 'Operadores do PedeOn' :
                            (widget.waitersOnly ? 'Garçons PedeOn' : 'Operadores PDV'),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        widget.pedeonOnly
                            ? 'Acessos exclusivos do aplicativo PedeOn'
                            : (widget.waitersOnly
                                ? 'Acessos móveis para lançamento de pedidos'
                                : 'Operadores do PDV legado'),
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo operador'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: _operators.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum operador cadastrado.'),
                      )
                    : Column(
                        children: [
                          for (final operator in _operators)
                            ListTile(
                              leading: Icon(
                                operator.isFiscal
                                    ? Icons.verified_user_outlined
                                    : Icons.point_of_sale_outlined,
                              ),
                              title: Text(operator.name),
                              subtitle: Text(
                                widget.pedeonOnly
                                    ? 'Usuário ${operator.code} | ${operator.active ? 'Ativo' : 'Inativo'}'
                                    : 'Código ${operator.code} | ${operator.isFiscal ? 'Fiscal' : 'Operador'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      _SmallChip(
                                        operator.active ? 'Ativo' : 'Inativo',
                                        operator.active
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      if (operator.canAuthorizeWithdrawal)
                                        const _SmallChip(
                                          'Sangria',
                                          Colors.blue,
                                        ),
                                      if (operator.canAuthorizeCancel)
                                        const _SmallChip(
                                          'Cancelamento',
                                          Colors.red,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Excluir operador',
                                    onPressed: () => _deleteOperator(operator),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              onTap: () => _openForm(operator),
                            ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OperatorDialog extends StatefulWidget {
  const _OperatorDialog({
    required this.api,
    required this.token,
    this.operator,
    this.waiterOnly = false,
    this.pedeonOnly = false,
  });

  final ApiClient api;
  final String token;
  final PdvOperator? operator;
  final bool waiterOnly;
  final bool pedeonOnly;

  @override
  State<_OperatorDialog> createState() => _OperatorDialogState();
}

class _OperatorDialogState extends State<_OperatorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.operator?.name ?? '');
  late final _code = TextEditingController(text: widget.operator?.code ?? '');
  final _pin = TextEditingController();
  late final _notes = TextEditingController(text: widget.operator?.notes ?? '');
  late String _role =
      widget.operator?.role ?? (widget.waiterOnly ? 'waiter' : (widget.pedeonOnly ? 'pedeon_operator' : 'operator'));
  late bool _active = widget.operator?.active ?? true;
  late bool _openCash = widget.operator?.canOpenCash ?? !widget.waiterOnly;
  late bool _withdrawal = widget.operator?.canAuthorizeWithdrawal ?? false;
  late bool _cancel = widget.operator?.canAuthorizeCancel ?? false;
  late bool _discount = widget.operator?.canAuthorizeDiscount ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _pin.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _applyRoleDefaults(String role) {
    setState(() {
      _role = role;
      if (role == 'fiscal') {
        _openCash = true;
        _withdrawal = true;
        _cancel = true;
        _discount = true;
      } else if (role == 'waiter') {
        _openCash = false;
        _withdrawal = false;
        _cancel = false;
        _discount = false;
      } else if (role == 'pedeon_operator') {
        _openCash = true;
        _withdrawal = false;
        _cancel = false;
        _discount = false;
      } else {
        _openCash = true;
        _withdrawal = false;
        _cancel = false;
        _discount = false;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = PdvOperatorPayload(
        name: _name.text,
        code: _code.text,
        pin: _pin.text,
        role: _role,
        canOpenCash: _openCash,
        canAuthorizeWithdrawal: _withdrawal,
        canAuthorizeCancel: _cancel,
        canAuthorizeDiscount: _discount,
        active: _active,
        notes: _notes.text,
      );
      if (widget.operator == null) {
        await widget.api.createPdvOperator(widget.token, payload);
      } else {
        await widget.api.updatePdvOperator(
          widget.token,
          widget.operator!.id,
          payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar operador.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.operator == null;
    return AlertDialog(
        title: Text(
              widget.waiterOnly
              ? (creating ? 'Novo garçom PedeOn' : 'Editar garçom PedeOn')
              : widget.pedeonOnly
              ? (creating ? 'Novo operador PedeOn' : 'Editar operador PedeOn')
              : (creating ? 'Novo operador PDV' : 'Editar operador PDV'),
        ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  ErrorPanel(
                    message: _error!,
                    onRetry: () => setState(() => _error = null),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Informe o nome.'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        decoration: InputDecoration(
                          labelText: widget.pedeonOnly ? 'Usuário' : 'Código',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                            ? 'Informe o código.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pin,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: widget.pedeonOnly
                              ? (creating ? 'Senha' : 'Nova senha')
                              : (creating ? 'Senha/PIN' : 'Nova senha/PIN'),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (creating && (value == null || value.length < 4)) {
                            return 'Mínimo 4 caracteres.';
                          }
                          if (!creating &&
                              value != null &&
                              value.isNotEmpty &&
                              value.length < 4) {
                            return 'Mínimo 4 caracteres.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!widget.waiterOnly && !widget.pedeonOnly)
                  DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'operator',
                      child: Text('Operador de caixa'),
                    ),
                    DropdownMenuItem(
                      value: 'fiscal',
                      child: Text('Fiscal / supervisor'),
                    ),
                  ],
                  onChanged: (value) => _applyRoleDefaults(value ?? 'operator'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Ativo'),
                ),
                if (!widget.waiterOnly)
                  CheckboxListTile(
                  value: _openCash,
                  onChanged: (value) =>
                      setState(() => _openCash = value ?? true),
                  title: const Text('Pode abrir caixa'),
                ),
                if (!widget.waiterOnly && !widget.pedeonOnly)
                  CheckboxListTile(
                  value: _withdrawal,
                  onChanged: (value) =>
                      setState(() => _withdrawal = value ?? false),
                  title: const Text('Pode autorizar sangria'),
                ),
                if (!widget.waiterOnly && !widget.pedeonOnly)
                  CheckboxListTile(
                  value: _cancel,
                  onChanged: (value) =>
                      setState(() => _cancel = value ?? false),
                  title: const Text('Pode autorizar cancelamentos'),
                ),
                if (!widget.waiterOnly && !widget.pedeonOnly)
                  CheckboxListTile(
                  value: _discount,
                  onChanged: (value) =>
                      setState(() => _discount = value ?? false),
                  title: const Text('Pode autorizar descontos'),
                ),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

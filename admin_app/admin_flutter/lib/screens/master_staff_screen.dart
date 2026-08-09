import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/master_staff.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MasterStaffScreen extends StatefulWidget {
  const MasterStaffScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterStaffScreen> createState() => _MasterStaffScreenState();
}

class _MasterStaffScreenState extends State<MasterStaffScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<MasterStaff> _staff = [];
  List<MasterPermission> _permissions = [];
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
      final results = await Future.wait([
        _api.listMasterStaff(widget.session.token),
        _api.listMasterPermissions(widget.session.token),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = results[0] as List<MasterStaff>;
        _permissions = results[1] as List<MasterPermission>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([MasterStaff? staff]) async {
    final input = await showDialog<MasterStaffInput>(
      context: context,
      builder: (context) =>
          _MasterStaffDialog(permissions: _permissions, staff: staff),
    );
    if (input == null) return;
    try {
      if (staff == null) {
        await _api.createMasterStaff(widget.session.token, input);
      } else {
        await _api.updateMasterStaff(widget.session.token, staff.id, input);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            staff == null
                ? 'Acesso do funcionário criado.'
                : 'Acesso do funcionário atualizado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Equipe',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF142033),
                          ),
                    ),
                    const Gap(6),
                    const Text(
                      'Crie acessos internos e libere somente as áreas necessárias.',
                      style: TextStyle(color: Color(0xFF60708A), fontSize: 16),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              const Gap(12),
              FilledButton.icon(
                onPressed: _loading ? null : () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Novo funcionário'),
              ),
            ],
          ),
          const Gap(22),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);
    if (_staff.isEmpty) {
      return AppCard(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 44,
                color: Color(0xFF60708A),
              ),
              const Gap(12),
              const Text(
                'Nenhum funcionário cadastrado.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Gap(14),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Criar primeiro acesso'),
              ),
            ],
          ),
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        itemCount: _staff.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = _staff[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            leading: CircleAvatar(
              child: Text(
                user.name.trim().isEmpty
                    ? '?'
                    : user.name.trim()[0].toUpperCase(),
              ),
            ),
            title: Text(
              user.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${user.email} • ${user.permissions.length} permissão(ões)',
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(user.active ? 'Ativo' : 'Inativo'),
                  backgroundColor: user.active
                      ? const Color(0xFFE8F7EF)
                      : const Color(0xFFF3F4F6),
                ),
                IconButton.outlined(
                  tooltip: 'Editar',
                  onPressed: () => _openForm(user),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MasterStaffDialog extends StatefulWidget {
  const _MasterStaffDialog({required this.permissions, this.staff});

  final List<MasterPermission> permissions;
  final MasterStaff? staff;

  @override
  State<_MasterStaffDialog> createState() => _MasterStaffDialogState();
}

class _MasterStaffDialogState extends State<_MasterStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late bool _active;
  late bool _mustChangePassword;
  late final Set<String> _selected;

  bool get _editing => widget.staff != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.staff?.name ?? '');
    _email = TextEditingController(text: widget.staff?.email ?? '');
    _active = widget.staff?.active ?? true;
    _mustChangePassword = widget.staff?.mustChangePassword ?? true;
    _selected = {...(widget.staff?.permissions ?? const [])};
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MasterStaffInput(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        active: _active,
        mustChangePassword: _mustChangePassword,
        permissions: _selected.toList()..sort(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<MasterPermission>>{};
    for (final permission in widget.permissions) {
      grouped.putIfAbsent(permission.module, () => []).add(permission);
    }
    final availableHeight = MediaQuery.sizeOf(context).height * 0.78;
    return AlertDialog(
      title: Text(_editing ? 'Editar funcionário' : 'Novo funcionário'),
      content: SizedBox(
        width: 720,
        height: availableHeight,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Informe o nome.'
                      : null,
                ),
                const Gap(12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (value) => (value ?? '').contains('@')
                      ? null
                      : 'Informe um e-mail válido.',
                ),
                const Gap(12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  onFieldSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: _editing
                        ? 'Nova senha opcional'
                        : 'Senha provisória',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (!_editing && text.length < 8) {
                      return 'Informe uma senha com pelo menos 8 caracteres.';
                    }
                    if (_editing && text.isNotEmpty && text.length < 8) {
                      return 'A senha precisa ter pelo menos 8 caracteres.';
                    }
                    return null;
                  },
                ),
                const Gap(8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  title: const Text('Acesso ativo'),
                  onChanged: (value) => setState(() => _active = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _mustChangePassword,
                  title: const Text('Exigir troca de senha no primeiro acesso'),
                  onChanged: (value) {
                    setState(() => _mustChangePassword = value);
                  },
                ),
                const Divider(height: 28),
                for (final entry in grouped.entries)
                  _PermissionGroup(
                    title: entry.key,
                    permissions: entry.value,
                    selected: _selected,
                    onChanged: (permission, selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(permission.code);
                        } else {
                          _selected.remove(permission.code);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({
    required this.title,
    required this.permissions,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<MasterPermission> permissions;
  final Set<String> selected;
  final void Function(MasterPermission permission, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD8E2F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF60708A),
                ),
              ),
              const Gap(6),
              for (final permission in permissions)
                CheckboxListTile(
                  value: selected.contains(permission.code),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(permission.label),
                  subtitle: Text(permission.description),
                  onChanged: (value) => onChanged(permission, value ?? false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

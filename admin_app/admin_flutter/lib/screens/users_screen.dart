import 'package:flutter/material.dart';

import '../models/session.dart';
import '../models/system_user.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _roleFallbackLabels = {
  'admin': 'Administrador',
  'technician': 'Técnico',
  'seller': 'Vendedor',
  'cashier': 'Operador de caixa',
  'client': 'Cliente',
};

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.session});

  final Session session;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<SystemUser> _users = [];
  List<SystemRole> _roles = [];
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
        _api.listSystemUsers(widget.session.token),
        _api.listSystemRoles(widget.session.token),
      ]);
      setState(() {
        _users = results[0] as List<SystemUser>;
        _roles = results[1] as List<SystemRole>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar usuários.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([SystemUser? user]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _UserDialog(
        api: _api,
        token: widget.session.token,
        user: user,
        roles: _roles,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteUser(SystemUser user) async {
    if (user.role == 'admin') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir usuário?'),
        content: Text(
          'Deseja realmente excluir o usuário "${user.name}"? Esta ação não pode ser desfeita.',
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
      await _api.deleteSystemUser(widget.session.token, user.id);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _roleLabel(String role) {
    for (final item in _roles) {
      if (item.name == role) return item.label;
    }
    return _roleFallbackLabels[role] ?? role;
  }

  @override
  Widget build(BuildContext context) {
    final activeUsers = _users.where((user) => user.active).length;
    final admins = _users.where((user) => user.role == 'admin').length;
    final canCreate = _roles.isNotEmpty;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Usuários',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Cadastre usuários e vincule cada pessoa a um perfil de acesso.',
                        style: TextStyle(color: Color(0xFF64748B)),
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
                  onPressed: canCreate ? () => _openForm() : null,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Novo usuário'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!canCreate && !_loading)
              const _ProfilesWarning()
            else
              _UsersSummaryGrid(
                items: [
                  _UsersSummaryItem(
                    'Usuários',
                    '${_users.length}',
                    Icons.groups_outlined,
                  ),
                  _UsersSummaryItem(
                    'Ativos',
                    '$activeUsers',
                    Icons.verified_user_outlined,
                  ),
                  _UsersSummaryItem(
                    'Administradores',
                    '$admins',
                    Icons.admin_panel_settings_outlined,
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
                child: _users.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum usuário cadastrado.'),
                      )
                    : _UsersTable(
                        users: _users,
                        roleLabel: _roleLabel,
                        onEdit: _openForm,
                        onDelete: _deleteUser,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfilesWarning extends StatelessWidget {
  const _ProfilesWarning();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2563EB)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Crie perfis em Configurações antes de cadastrar novos usuários.',
              style: TextStyle(color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.roleLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SystemUser> users;
  final String Function(String role) roleLabel;
  final ValueChanged<SystemUser> onEdit;
  final ValueChanged<SystemUser> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: const Row(
            children: [
              Expanded(flex: 3, child: _HeaderCell('Usuário')),
              SizedBox(width: 140, child: _HeaderCell('Cód. vendedor')),
              SizedBox(width: 220, child: _HeaderCell('Perfil')),
              SizedBox(width: 120, child: _HeaderCell('Status')),
              SizedBox(width: 112, child: _HeaderCell('Ações')),
            ],
          ),
        ),
        for (final user in users)
          Container(
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 140, child: Text(user.sellerCode ?? '-')),
                SizedBox(width: 220, child: Text(roleLabel(user.role))),
                SizedBox(width: 120, child: _StatusPill(active: user.active)),
                SizedBox(
                  width: 112,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Editar usuário',
                        onPressed: () => onEdit(user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: user.role == 'admin'
                            ? 'Administrador não pode ser excluído'
                            : 'Excluir usuário',
                        onPressed: user.role == 'admin'
                            ? null
                            : () => onDelete(user),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({
    required this.api,
    required this.token,
    required this.roles,
    this.user,
  });

  final ApiClient api;
  final String token;
  final List<SystemRole> roles;
  final SystemUser? user;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _sellerCode;
  late final TextEditingController _technicianCode;
  late final TextEditingController _password;
  late String _role;
  late bool _active;
  late bool _appAccess;
  late bool _discountOverride;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user?.name ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _sellerCode = TextEditingController(text: user?.sellerCode ?? '');
    _technicianCode = TextEditingController(text: user?.technicianCode ?? '');
    _password = TextEditingController();
    final userRole = user?.role;
    final roleExists = widget.roles.any((role) => role.name == userRole);
    _role = roleExists && userRole != null ? userRole : widget.roles.first.name;
    _active = user?.active ?? true;
    _appAccess = user?.permissions.contains('app:access') ?? false;
    _discountOverride =
        user?.permissions.contains('sales:discount:override') ??
        (_selectedRole?.permissions.contains('sales:discount:override') ??
            false);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _sellerCode.dispose();
    _technicianCode.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save({bool allowCrossCompanyDuplicate = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = SystemUserPayload(
      name: _name.text,
      email: _email.text,
      sellerCode: _selectedRole?.isSellerProfile == true
          ? _sellerCode.text
          : null,
      technicianCode: _selectedRole?.isTechnicianProfile == true
          ? _technicianCode.text
          : null,
      password: _password.text.trim().isEmpty ? null : _password.text,
      role: _role,
      active: _active,
      appAccess: _appAccess,
      allowCrossCompanyDuplicate: allowCrossCompanyDuplicate,
    );
    try {
      late final SystemUser savedUser;
      if (_editing) {
        savedUser = await widget.api.updateSystemUser(
          widget.token,
          widget.user!.id,
          payload,
        );
      } else {
        savedUser = await widget.api.createSystemUser(widget.token, payload);
      }
      await widget.api.setSystemUserPermission(
        widget.token,
        savedUser.id,
        permissionCode: 'sales:discount:override',
        allowed: _discountOverride,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (await _showDuplicateEmailBlock(error)) return;
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o usuário.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _showDuplicateEmailBlock(ApiException error) async {
    final detail = error.data?['detail'];
    if (detail is! Map<String, dynamic>) return false;
    if (detail['code'] != 'email_exists_other_companies') return false;
    final companies = detail['companies'];
    if (companies is! List) return false;
    final companyLines = companies
        .whereType<Map<String, dynamic>>()
        .map(
          (company) =>
              '${company['company_name'] ?? company['company_code']} - ${company['access_url'] ?? ''}',
        )
        .join('\n');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-mail já usado em outro cliente'),
        content: Text(
          'Este e-mail já existe em outro sistema:\n\n$companyLines\n\nUse outro e-mail para evitar conflito no login.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() => _error = 'Este e-mail já está em uso em outro cliente.');
    }
    return true;
  }

  SystemRole? get _selectedRole {
    for (final role in widget.roles) {
      if (role.name == _role) return role;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Editar usuário' : 'Novo usuário'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  _InlineError(message: _error!),
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
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Informe um e-mail válido.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (_selectedRole?.isSellerProfile == true) ...[
                  TextFormField(
                    controller: _sellerCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código vendedor',
                      helperText:
                          'Opcional. Use quando esse usuário também vender no sistema.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe o codigo de vendedor.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_selectedRole?.isTechnicianProfile == true) ...[
                  TextFormField(
                    controller: _technicianCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Codigo tecnico',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe o codigo de tecnico.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _editing
                        ? 'Nova senha (opcional)'
                        : 'Senha provisória',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (!_editing && password.length < 8) {
                      return 'A senha precisa ter pelo menos 8 caracteres.';
                    }
                    if (_editing &&
                        password.isNotEmpty &&
                        password.length < 8) {
                      return 'A senha precisa ter pelo menos 8 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Perfil',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem(
                        value: role.name,
                        child: Text(role.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.phone_android_outlined),
                  title: const Text('Permitir acesso ao aplicativo Lyncar'),
                  subtitle: const Text(
                    'Sem isso, o usuário não consegue entrar no app Android/iOS.',
                  ),
                  value: _appAccess,
                  onChanged: (value) => setState(() => _appAccess = value),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.percent_outlined),
                  title: const Text('Desconto livre'),
                  subtitle: const Text(
                    'Permite este usuario ultrapassar o limite de desconto em vendas e OS.',
                  ),
                  value: _discountOverride,
                  onChanged: (value) =>
                      setState(() => _discountOverride = value),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usuário ativo'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
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
          label: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}

class _UsersSummaryGrid extends StatelessWidget {
  const _UsersSummaryGrid({required this.items});

  final List<_UsersSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 5 : 2.8,
          children: [for (final item in items) _UsersSummaryCard(item: item)],
        );
      },
    );
  }
}

class _UsersSummaryCard extends StatelessWidget {
  const _UsersSummaryCard({required this.item});

  final _UsersSummaryItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.label,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              Text(
                item.value,
                style: const TextStyle(
                  fontSize: 28,
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

class _UsersSummaryItem {
  const _UsersSummaryItem(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          active ? 'Ativo' : 'Inativo',
          style: TextStyle(
            color: active ? const Color(0xFF166534) : const Color(0xFF991B1B),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

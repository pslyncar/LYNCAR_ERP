import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';

import '../models/fiscal.dart';
import '../models/session.dart';
import '../models/system_user.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import 'fiscal_screen.dart';

const _moduleLabels = {
  'clients': 'Clientes',
  'equipments': 'Equipamentos',
  'tickets': 'Chamados',
  'products': 'Produtos',
  'stock': 'Estoque',
  'stock_entries': 'Entradas',
  'stock_withdrawals': 'Baixas',
  'suppliers': 'Fornecedores',
  'production': 'Produção',
  'service_contracts': 'Contratos variáveis',
  'sales': 'Vendas',
  'cash_closings': 'Caixa e tesouraria',
  'pdv': 'Vendas de PDV',
  'pdv_windows': 'PDV Windows',
  'service_orders': 'Ordens de serviço',
  'monitoring': 'Monitoramento',
  'dashboard': 'Início',
  'reports': 'Relatórios',
  'finance': 'Financeiro',
  'fiscal': 'Fiscal',
  'marketplaces': 'Marketplaces',
  'support': 'Suporte',
  'settings': 'Configuracoes',
  'users': 'Usuários',
  'permissions': 'Permissões',
};

const _moduleDescriptions = {
  'clients': 'Cadastro de clientes, dados de contato e crediário.',
  'products': 'Produtos, preços, estoque e códigos de barras.',
  'stock': 'Estoque, produtos e lotes/validade.',
  'stock_entries': 'Entradas, XML de compra e conferência de mercadoria.',
  'stock_withdrawals': 'Baixas de estoque por perda, consumo e vencimento.',
  'suppliers': 'Cadastro de fornecedores usados nas compras.',
  'service_contracts':
      'Contratos recorrentes por apontamento, baixa de produtos e fechamento quinzenal.',
  'sales': 'Venda manual administrativa e consulta do histórico de vendas.',
  'pdv': 'PDV Web/caixa, operadores, fiscais e autorizações.',
  'finance': 'Contas a pagar, contas a receber e baixas.',
  'fiscal': 'Certificado, NFC-e/NF-e e documentos fiscais.',
  'marketplaces':
      'Mercado Livre e outros canais de venda integrados ao estoque.',
  'support': 'Abertura e acompanhamento de chamados com o suporte.',
  'settings': 'Configuracoes',
  'dashboard': 'Tela inicial, avisos e indicadores.',
  'reports': 'Relatórios e exportações.',
  'users': 'Cadastro de usuários do sistema.',
  'permissions': 'Criação de perfis e liberação de acessos.',
  'production': 'Ordens de produção e baixa de insumos.',
  'service_orders': 'Ordens de serviço e atendimento técnico.',
  'monitoring': 'Monitoramento de equipamentos.',
  'equipments': 'Equipamentos vinculados a clientes.',
  'tickets': 'Chamados e solicitações.',
};

const _moduleQuickGuides = {
  'pdv': 'Controla somente o botão PDV Web/caixa. Não libera a tela Vendas.',
  'sales':
      'Controla a venda manual administrativa e o histórico. Não libera o PDV Web.',
  'service_contracts':
      'Use para empresas que cobram por atendimento/quinzena. Ver contratos só consulta; Gerenciar cria regras e produtos; Apontar confirma dias e baixa estoque; Fechar gera contas a receber.',
  'clients':
      'Use só se o usuário puder ver ou cadastrar clientes. Para caixa simples, pode ficar desmarcado.',
  'products':
      'Ver produtos ajuda o usuário a consultar itens. Criar/editar/excluir muda o cadastro.',
  'stock':
      'Ver estoque permite consultar saldo. Entradas/conferência são para compras e recebimento.',
  'finance':
      'Libera contas a receber, contas a pagar, crediário e baixas financeiras.',
  'fiscal':
      'Libera configurações fiscais, certificados e documentos NFC-e/NF-e quando contratado.',
  'marketplaces':
      'Libera Mercado Livre e escolha dos produtos sincronizados com estoque.',
  'users':
      'Libera criar e alterar usuários. Normalmente fica só para dono/gerente.',
  'permissions':
      'Libera criar perfis de acesso. Normalmente fica só para dono/gerente.',
  'reports':
      'Libera relatórios. Alguns relatórios também dependem do módulo de origem.',
};

const _permissionUsageHints = {
  'dashboard:view': 'Mostra o botão Início.',
  'clients:view': 'Mostra o botão Clientes e permite consultar clientes.',
  'clients:create': 'Permite cadastrar novo cliente.',
  'clients:update': 'Permite alterar cadastro de cliente.',
  'clients:delete': 'Permite excluir cliente.',
  'products:view':
      'Mostra Produtos/Estoque quando combinado com estoque e permite consultar itens.',
  'products:create': 'Permite cadastrar produto.',
  'products:update': 'Permite alterar produto, preço e dados do cadastro.',
  'products:delete': 'Permite excluir produto.',
  'stock:view': 'Mostra Estoque e permite consultar saldo.',
  'stock:move': 'Permite movimentar estoque manualmente.',
  'app:access':
      'Permite entrar no aplicativo Android/iOS. Sem esta permissão o login do app é bloqueado.',
  'stock:withdraw':
      'Mostra apenas Baixas e registra perdas, consumo e outras saídas no nome do usuário logado.',
  'stock:entries:view': 'Mostra Entradas e permite consultar recebimentos.',
  'stock:entries:create': 'Permite lançar entrada de mercadoria.',
  'stock:entries:confirm':
      'Permite finalizar conferência e movimentar estoque.',
  'stock:entries:return': 'Permite marcar divergência/devolução na entrada.',
  'stock:entries:create_product_from_xml':
      'Permite criar produto a partir de XML de compra.',
  'stock:batches:view': 'Permite ver lotes e validades.',
  'suppliers:view': 'Mostra Fornecedores e permite consultar fornecedores.',
  'suppliers:create': 'Permite cadastrar fornecedor.',
  'suppliers:update': 'Permite alterar fornecedor.',
  'suppliers:delete': 'Permite excluir fornecedor.',
  'production:view': 'Mostra Produção e permite consultar ordens.',
  'production:create': 'Permite criar ordem de produção e baixar insumos.',
  'service_contracts:view':
      'Mostra Contratos e permite consultar contratos e apontamentos.',
  'service_contracts:manage':
      'Permite criar/editar contratos, regras, feriados e produtos vinculados.',
  'service_contracts:appointments':
      'Permite gerar, editar, confirmar e cancelar apontamentos; confirmar baixa estoque.',
  'service_contracts:billing':
      'Permite fechar quinzena e gerar contas a receber.',
  'sales:view': 'Mostra a aba Histórico no menu Vendas.',
  'sales:manual':
      'Mostra o menu Vendas e permite criar venda manual fora do PDV.',
  'sales:create': 'Mostra o botão PDV Web e permite vender no caixa.',
  'sales:cancel': 'Permite cancelar venda e estornar estoque.',
  'sales:discount:override':
      'Permite ultrapassar o limite de desconto na venda manual e na venda da OS.',
  'pdv_operators:manage':
      'Mostra Op. PDV e permite cadastrar operadores/fiscais do caixa.',
  'cash_closings:manage':
      'Permite aprovar, corrigir e marcar divergencias em Caixa e tesouraria.',
  'finance:view': 'Mostra Financeiro.',
  'finance:receivables:view': 'Permite ver contas a receber e crediário.',
  'finance:receivables:pay': 'Permite baixar/receber contas a receber.',
  'finance:payables:view': 'Permite ver contas a pagar.',
  'finance:payables:manage': 'Permite criar, alterar e baixar contas a pagar.',
  'fiscal:view': 'Mostra área fiscal e status/configurações fiscais.',
  'fiscal:settings': 'Permite alterar certificado e configuração fiscal.',
  'fiscal:emit': 'Permite preparar/emissão fiscal quando disponível.',
  'fiscal:documents:view': 'Permite consultar documentos fiscais/XMLs.',
  'marketplaces:view': 'Mostra o menu Marketplaces.',
  'marketplaces:connect': 'Permite copiar o link de conexao com Mercado Livre.',
  'marketplaces:products':
      'Permite escolher quais produtos serao publicados e sincronizados.',
  'reports:view': 'Mostra Relatórios.',
  'users:manage': 'Mostra Usuários e permite criar/alterar usuários.',
  'permissions:manage': 'Permite criar e alterar perfis de acesso.',
};

const _profilePresets = [
  _ProfilePreset(
    'App baixas',
    'Entra no aplicativo e registra saídas justificadas do estoque.',
    {'app:access', 'stock:withdraw'},
  ),
  _ProfilePreset(
    'App recebimento',
    'Entra no aplicativo para conferir recebimentos de mercadoria.',
    {'app:access', 'stock:entries:view', 'stock:entries:create'},
  ),
  _ProfilePreset('Somente PDV', 'Abre o PDV e registra vendas no caixa.', {
    'dashboard:view',
    'products:view',
    'stock:view',
    'stock:batches:view',
    'sales:create',
  }),
  _ProfilePreset('Vendedor', 'Vende, consulta clientes e acompanha produtos.', {
    'dashboard:view',
    'clients:view',
    'clients:create',
    'clients:update',
    'products:view',
    'stock:view',
    'sales:view',
    'sales:manual',
    'reports:view',
  }),
  _ProfilePreset('Financeiro', 'Cuida das contas a pagar, receber e baixas.', {
    'dashboard:view',
    'clients:view',
    'finance:view',
    'finance:receivables:view',
    'finance:receivables:pay',
    'finance:payables:view',
    'finance:payables:manage',
    'reports:view',
  }),
  _ProfilePreset(
    'Estoque / Compras',
    'Cadastra fornecedores, entradas e conferência de mercadoria.',
    {
      'dashboard:view',
      'products:view',
      'products:create',
      'products:update',
      'stock:view',
      'stock:entries:view',
      'stock:entries:create',
      'stock:entries:confirm',
      'stock:entries:return',
      'stock:entries:create_product_from_xml',
      'stock:batches:view',
      'suppliers:view',
      'suppliers:create',
      'suppliers:update',
      'suppliers:delete',
    },
  ),
  _ProfilePreset(
    'Gerente',
    'Acompanha a operação e resolve exceções do dia a dia.',
    {
      'dashboard:view',
      'clients:view',
      'clients:create',
      'clients:update',
      'products:view',
      'products:create',
      'products:update',
      'stock:view',
      'stock:entries:view',
      'sales:view',
      'sales:manual',
      'sales:create',
      'sales:cancel',
      'pdv_operators:manage',
      'finance:view',
      'finance:receivables:view',
      'finance:payables:view',
      'reports:view',
    },
  ),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _selectedKey;

  bool get _canOpenFiscal {
    return widget.session.canUseFiscal &&
        (widget.session.can('fiscal:view') ||
            widget.session.can('fiscal:settings') ||
            widget.session.can('fiscal:documents:view'));
  }

  bool get _canOpenProfiles => widget.session.can('permissions:manage');
  bool get _canOpenSalesSettings => widget.session.can('permissions:manage');
  bool get _canOpenPdvLogo =>
      widget.session.hasModule('pdv_windows') &&
      widget.session.can('pdv_operators:manage');

  @override
  void initState() {
    super.initState();
    if (_canOpenProfiles) {
      _selectedKey = 'profiles';
    } else if (_canOpenPdvLogo) {
      _selectedKey = 'pdv_logo';
    } else if (_canOpenFiscal) {
      _selectedKey = 'fiscal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      if (_canOpenProfiles)
        _SettingsOption(
          keyName: 'profiles',
          title: 'Perfis de acesso',
          subtitle: 'Crie cargos e defina o que cada usuário pode fazer',
          icon: Icons.admin_panel_settings_outlined,
          screen: AccessProfilesPanel(session: widget.session),
        ),
      if (_canOpenSalesSettings)
        _SettingsOption(
          keyName: 'sales',
          title: 'Vendas',
          subtitle: 'Limite de desconto da venda manual e da OS',
          icon: Icons.sell_outlined,
          screen: SalesSettingsPanel(session: widget.session),
        ),
      if (_canOpenPdvLogo)
        _SettingsOption(
          keyName: 'pdv_logo',
          title: 'Logo do PDV Windows',
          subtitle: 'Foto da tela OBRIGADO do aplicativo Windows',
          icon: Icons.image_outlined,
          screen: PdvLogoSettingsPanel(session: widget.session),
        ),
      if (_canOpenFiscal)
        _SettingsOption(
          keyName: 'fiscal',
          title: 'Fiscal',
          subtitle: 'Certificado A1, CSC/ID, séries e cadastro tributário',
          icon: Icons.receipt_long_outlined,
          screen: FiscalScreen(session: widget.session),
        ),
    ];

    final selected = options.where((item) => item.keyName == _selectedKey);
    final selectedOption = selected.isEmpty ? null : selected.first;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final content = options.isEmpty
              ? const _EmptySettingsPanel()
              : compact
              ? Column(
                  children: [
                    _SettingsOptionsList(
                      options: options,
                      selectedKey: _selectedKey,
                      onSelect: (key) => setState(() => _selectedKey = key),
                    ),
                    const Gap(14),
                    Expanded(
                      child: selectedOption == null
                          ? const AppCard(
                              child: Text('Selecione uma configuração.'),
                            )
                          : selectedOption.screen,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _SettingsOptionsList(
                        options: options,
                        selectedKey: _selectedKey,
                        onSelect: (key) => setState(() => _selectedKey = key),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: selectedOption == null
                          ? const AppCard(
                              child: Text('Selecione uma configuração.'),
                            )
                          : selectedOption.screen,
                    ),
                  ],
                );

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configurações',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Parâmetros do sistema que não fazem parte da operação diária',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),
                Expanded(child: content),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SalesSettingsPanel extends StatefulWidget {
  const SalesSettingsPanel({super.key, required this.session});

  final Session session;

  @override
  State<SalesSettingsPanel> createState() => _SalesSettingsPanelState();
}

class _SalesSettingsPanelState extends State<SalesSettingsPanel> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _maxDiscount = TextEditingController(text: '100,00');
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxDiscount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _api.getSalesSettings(widget.session.token);
      if (!mounted) return;
      setState(() {
        _maxDiscount.text = formatBrazilianMoneyInput(
          settings.maxDiscountPercent,
        );
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar as configurações.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final value = parseBrazilianNumber(_maxDiscount.text);
    if (value < 0 || value > 100) {
      setState(() => _error = 'Informe um percentual entre 0% e 100%.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = await _api.updateSalesSettings(
        widget.session.token,
        value,
      );
      if (!mounted) return;
      setState(() {
        _maxDiscount.text = formatBrazilianMoneyInput(
          settings.maxDiscountPercent,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações de vendas salvas.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar as configurações.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppCard(child: Center(child: CircularProgressIndicator()));
    }
    return AppCard(
      child: ListView(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.sell_outlined,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vendas',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Controle o desconto máximo da venda manual e da venda gerada pela OS.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Recarregar',
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _maxDiscount,
            keyboardType: TextInputType.text,
            inputFormatters: const [BrazilianMoneyInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Desconto máximo permitido (%)',
              helperText:
                  'Ex.: 5,00 permite desconto até 5% do subtotal. O PDV não usa esta regra.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar'),
            ),
          ),
        ],
      ),
    );
  }
}

class PdvLogoSettingsPanel extends StatefulWidget {
  const PdvLogoSettingsPanel({super.key, required this.session});

  final Session session;

  @override
  State<PdvLogoSettingsPanel> createState() => _PdvLogoSettingsPanelState();
}

class _PdvLogoSettingsPanelState extends State<PdvLogoSettingsPanel> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _logoUrl = TextEditingController();
  CompanyFiscalSetting? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _logoUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _api.getPdvLogoSettings(widget.session.token);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _logoUrl.text = settings.logoUrl ?? '';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final extension = (file?.extension ?? '').toLowerCase();
    const allowedExtensions = {
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'tif',
      'tiff',
      'jfif',
    };
    if (!allowedExtensions.contains(extension)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma imagem PNG, JPG, WEBP, GIF ou BMP.'),
        ),
      );
      return;
    }
    final mime = switch (extension) {
      'jpg' || 'jpeg' || 'jfif' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'tif' || 'tiff' => 'image/tiff',
      _ => 'image/png',
    };
    setState(() {
      _logoUrl.text = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updatePdvLogoSettings(
        widget.session.token,
        _logoUrl.text.trim().isEmpty ? null : _logoUrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _logoUrl.text = updated.logoUrl ?? '';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logo do PDV salva.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _preview() {
    final value = _logoUrl.text.trim();
    if (value.isEmpty) {
      return const Center(child: Text('Nenhuma logo selecionada.'));
    }
    final comma = value.indexOf(',');
    if (value.startsWith('data:image/') && comma > 0) {
      try {
        final bytes = base64Decode(value.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        return const Center(child: Text('Imagem invalida.'));
      }
    }
    return const Center(child: Text('Logo salva.'));
  }

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
                      'Logo do PDV Windows',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Imagem exibida na tela OBRIGADO do aplicativo Windows depois da venda.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _loading ? null : _load,
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
          SizedBox(
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: const Color(0xFFD8E2EF)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: _preview()),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Selecionar imagem'),
              ),
              FilledButton.icon(
                onPressed: _saving || _logoUrl.text.trim().isEmpty
                    ? null
                    : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar logo'),
              ),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() => _logoUrl.clear());
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Limpar'),
              ),
            ],
          ),
          if (_settings?.logoUrl?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            const Text(
              'Logo salva no cadastro.',
              style: TextStyle(color: Color(0xFF166534)),
            ),
          ],
        ],
      ),
    );
  }
}

class AccessProfilesPanel extends StatefulWidget {
  const AccessProfilesPanel({super.key, required this.session});

  final Session session;

  @override
  State<AccessProfilesPanel> createState() => _AccessProfilesPanelState();
}

class _AccessProfilesPanelState extends State<AccessProfilesPanel> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<SystemRole> _roles = [];
  List<SystemPermission> _permissions = [];
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
        _api.listSystemRoles(widget.session.token),
        _api.listSystemPermissions(widget.session.token),
      ]);
      setState(() {
        _roles = results[0] as List<SystemRole>;
        _permissions = results[1] as List<SystemPermission>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar os perfis.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([SystemRole? role]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _AccessProfileDialog(
        api: _api,
        session: widget.session,
        token: widget.session.token,
        permissions: _permissions,
        role: role,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(SystemRole role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir perfil'),
        content: Text('Excluir o perfil "${role.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteSystemRole(widget.session.token, role.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
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
                      'Perfis de acesso',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Monte cargos da sua empresa usando apenas os módulos liberados no plano.',
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
              const Gap(8),
              FilledButton.icon(
                onPressed: _loading ? null : () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Novo perfil'),
              ),
            ],
          ),
          const Gap(16),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            ErrorPanel(message: _error!, onRetry: _load)
          else
            Expanded(
              child: _roles.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum perfil cadastrado. Crie o primeiro para liberar novos usuários.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: _roles.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final role = _roles[index];
                        final systemRole = role.name == 'admin';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEFF6FF),
                            child: Icon(
                              systemRole
                                  ? Icons.verified_user_outlined
                                  : Icons.badge_outlined,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          title: Text(
                            role.label,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            systemRole
                                ? 'Perfil do sistema com acesso administrativo.'
                                : '${role.permissions.length} acessos liberados',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: systemRole
                                    ? 'Perfil do sistema'
                                    : 'Editar perfil',
                                onPressed: systemRole
                                    ? null
                                    : () => _openForm(role),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: systemRole
                                    ? 'Perfil do sistema'
                                    : 'Excluir perfil',
                                onPressed: systemRole
                                    ? null
                                    : () => _delete(role),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _AccessProfileDialog extends StatefulWidget {
  const _AccessProfileDialog({
    required this.api,
    required this.session,
    required this.token,
    required this.permissions,
    this.role,
  });

  final ApiClient api;
  final Session session;
  final String token;
  final List<SystemPermission> permissions;
  final SystemRole? role;

  @override
  State<_AccessProfileDialog> createState() => _AccessProfileDialogState();
}

class _AccessProfileDialogState extends State<_AccessProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _description;
  late Set<String> _selected;
  late bool _isSellerProfile;
  late bool _isTechnicianProfile;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.role != null;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.role?.label ?? '');
    _description = TextEditingController(text: widget.role?.description ?? '');
    final available = widget.permissions.map((item) => item.code).toSet();
    _selected = (widget.role?.permissions ?? const <String>[])
        .where(available.contains)
        .toSet();
    _isSellerProfile =
        widget.session.sellerRoleEnabled &&
        (widget.role?.isSellerProfile ?? false);
    _isTechnicianProfile =
        widget.session.technicianRoleEnabled &&
        (widget.role?.isTechnicianProfile ?? false);
  }

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    super.dispose();
  }

  Map<String, List<SystemPermission>> get _grouped {
    final grouped = <String, List<SystemPermission>>{};
    for (final permission in widget.permissions) {
      grouped.putIfAbsent(permission.module, () => []).add(permission);
    }
    return grouped;
  }

  Set<String> get _availableCodes =>
      widget.permissions.map((permission) => permission.code).toSet();

  void _applyPreset(_ProfilePreset preset) {
    final available = _availableCodes;
    setState(() {
      _selected = preset.permissions.where(available.contains).toSet();
      if (_label.text.trim().isEmpty) {
        _label.text = preset.label;
      }
      if (_description.text.trim().isEmpty) {
        _description.text = preset.description;
      }
    });
  }

  void _toggleModule(List<SystemPermission> permissions, bool selected) {
    setState(() {
      final codes = permissions.map((permission) => permission.code);
      if (selected) {
        _selected.addAll(codes);
      } else {
        _selected.removeAll(codes);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = SystemRolePayload(
      label: _label.text,
      description: _description.text,
      permissions: _selected.toList()..sort(),
      isSellerProfile: _isSellerProfile,
      isTechnicianProfile: _isTechnicianProfile,
    );
    try {
      if (_editing) {
        await widget.api.updateSystemRole(
          widget.token,
          widget.role!.id,
          payload,
        );
      } else {
        await widget.api.createSystemRole(widget.token, payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o perfil.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final viewport = MediaQuery.sizeOf(context);
    final maxContentHeight = (viewport.height - 132)
        .clamp(460.0, 820.0)
        .toDouble();
    final dialogWidth = viewport.width < 900 ? viewport.width - 32 : 820.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      title: Text(_editing ? 'Editar perfil' : 'Novo perfil'),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxContentHeight),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    _InlineError(message: _error!),
                    const Gap(12),
                  ],
                  TextFormField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Nome do perfil',
                      hintText: 'Ex.: Caixa, Gerente, Estoque',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                        ? 'Informe o nome do perfil.'
                        : null,
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(14),
                  _OperationalRoleBox(
                    sellerAvailable: widget.session.sellerRoleEnabled,
                    technicianAvailable: widget.session.technicianRoleEnabled,
                    isSellerProfile: _isSellerProfile,
                    isTechnicianProfile: _isTechnicianProfile,
                    canOverrideDiscount: _selected.contains(
                      'sales:discount:override',
                    ),
                    onSellerChanged: (value) =>
                        setState(() => _isSellerProfile = value),
                    onTechnicianChanged: (value) =>
                        setState(() => _isTechnicianProfile = value),
                    onOverrideDiscountChanged: (value) {
                      setState(() {
                        if (value) {
                          _selected.add('sales:discount:override');
                        } else {
                          _selected.remove('sales:discount:override');
                        }
                      });
                    },
                  ),
                  const Gap(14),
                  const Gap(14),
                  const _PermissionHelpBox(),
                  const Gap(14),
                  _PresetPicker(
                    availableCodes: _availableCodes,
                    onApply: _applyPreset,
                  ),
                  const Gap(14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Acessos por módulo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _selected.clear()),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Limpar'),
                      ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Abra um módulo para ver o que cada acesso libera.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                  const Gap(8),
                  for (final entry in grouped.entries)
                    _PermissionModuleTile(
                      module: entry.key,
                      permissions: entry.value,
                      selected: _selected,
                      onToggleModule: _toggleModule,
                      onTogglePermission: (permission, selected) {
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

class _ProfilePreset {
  const _ProfilePreset(this.label, this.description, this.permissions);

  final String label;
  final String description;
  final Set<String> permissions;
}

class _OperationalRoleBox extends StatelessWidget {
  const _OperationalRoleBox({
    required this.sellerAvailable,
    required this.technicianAvailable,
    required this.isSellerProfile,
    required this.isTechnicianProfile,
    required this.canOverrideDiscount,
    required this.onSellerChanged,
    required this.onTechnicianChanged,
    required this.onOverrideDiscountChanged,
  });

  final bool sellerAvailable;
  final bool technicianAvailable;
  final bool isSellerProfile;
  final bool isTechnicianProfile;
  final bool canOverrideDiscount;
  final ValueChanged<bool> onSellerChanged;
  final ValueChanged<bool> onTechnicianChanged;
  final ValueChanged<bool> onOverrideDiscountChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD5E1F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Funcao do perfil',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (sellerAvailable)
              SwitchListTile(
                value: isSellerProfile,
                onChanged: onSellerChanged,
                title: const Text('Vendedor'),
                subtitle: const Text('Exige codigo de vendedor no usuario.'),
                contentPadding: EdgeInsets.zero,
              ),
            if (technicianAvailable)
              SwitchListTile(
                value: isTechnicianProfile,
                onChanged: onTechnicianChanged,
                title: const Text('Tecnico'),
                subtitle: const Text('Exige codigo de tecnico no usuario.'),
                contentPadding: EdgeInsets.zero,
              ),
            SwitchListTile(
              value: canOverrideDiscount,
              onChanged: onOverrideDiscountChanged,
              title: const Text('Desconto livre'),
              subtitle: const Text(
                'Permite ultrapassar o limite configurado em Vendas e OS.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionHelpBox extends StatelessWidget {
  const _PermissionHelpBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como pensar nos acessos',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          Gap(6),
          Text(
            'Para liberar apenas o botao PDV Web, use o modelo Somente PDV ou marque Operar PDV Web em Vendas de PDV. Isso nao libera a tela Vendas.',
            style: TextStyle(color: Color(0xFF475569), height: 1.35),
          ),
          Gap(8),
          Text(
            'Para liberar a venda administrativa, marque Criar venda manual em Vendas. Para liberar a aba de consulta, marque Ver historico de vendas.',
            style: TextStyle(color: Color(0xFF475569), height: 1.35),
          ),
          Gap(8),
          Text(
            'Evite Liberar tudo quando quiser acesso limitado. Use Liberar tudo somente para gerente/dono daquele módulo.',
            style: TextStyle(color: Color(0xFF475569), height: 1.35),
          ),
          Gap(8),
          Text(
            'Ver: consulta. Criar/Operar: cadastra ou registra. Editar: altera. Excluir: remove. Baixar: registra pagamento/recebimento. Gerenciar: controle completo.',
            style: TextStyle(color: Color(0xFF475569), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.availableCodes, required this.onApply});

  final Set<String> availableCodes;
  final ValueChanged<_ProfilePreset> onApply;

  @override
  Widget build(BuildContext context) {
    final presets = _profilePresets
        .where(
          (preset) => preset.permissions.every(
            (permission) => availableCodes.contains(permission),
          ),
        )
        .toList();
    if (presets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Começar por um modelo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const Gap(4),
        const Text(
          'Escolha um modelo e ajuste o que precisar depois.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const Gap(10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(preset.label),
                onPressed: () => onApply(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _PermissionModuleTile extends StatelessWidget {
  const _PermissionModuleTile({
    required this.module,
    required this.permissions,
    required this.selected,
    required this.onToggleModule,
    required this.onTogglePermission,
  });

  final String module;
  final List<SystemPermission> permissions;
  final Set<String> selected;
  final void Function(List<SystemPermission> permissions, bool selected)
  onToggleModule;
  final void Function(SystemPermission permission, bool selected)
  onTogglePermission;

  @override
  Widget build(BuildContext context) {
    final selectedCount = permissions
        .where((permission) => selected.contains(permission.code))
        .length;
    final allSelected =
        permissions.isNotEmpty && selectedCount == permissions.length;
    final moduleGuide = _moduleQuickGuides[module];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        title: Text(
          _moduleLabels[module] ?? module,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${_moduleDescriptions[module] ?? 'Acessos deste módulo.'} $selectedCount/${permissions.length} selecionado(s).',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(
              label: Text(allSelected ? 'Tudo' : 'Liberar tudo'),
              selected: allSelected,
              onSelected: (value) => onToggleModule(permissions, value),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          if (moduleGuide != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      moduleGuide,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final permission in permissions)
            CheckboxListTile(
              dense: true,
              value: selected.contains(permission.code),
              onChanged: (value) =>
                  onTogglePermission(permission, value ?? false),
              title: Text(
                permission.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  permission.description ?? permission.code,
                  if (_permissionUsageHints[permission.code] != null)
                    _permissionUsageHints[permission.code]!,
                ].join('\n'),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
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

class _EmptySettingsPanel extends StatelessWidget {
  const _EmptySettingsPanel();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: [
          Icon(Icons.tune_outlined, color: Color(0xFF64748B)),
          Gap(12),
          Expanded(
            child: Text(
              'Nenhuma configuração adicional liberada para esta empresa.',
              style: TextStyle(color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsOptionsList extends StatelessWidget {
  const _SettingsOptionsList({
    required this.options,
    required this.selectedKey,
    required this.onSelect,
  });

  final List<_SettingsOption> options;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          for (final option in options)
            _SettingsOptionTile(
              option: option,
              selected: option.keyName == selectedKey,
              onTap: () => onSelect(option.keyName),
            ),
        ],
      ),
    );
  }
}

class _SettingsOptionTile extends StatelessWidget {
  const _SettingsOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _SettingsOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFBFDBFE) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(
                  option.icon,
                  color: selected
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFF475569),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _SettingsOption {
  const _SettingsOption({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.screen,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget screen;
}

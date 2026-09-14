import 'package:flutter/material.dart';

import '../../../models/session.dart';
import '../data/pedeon_repository.dart';
import '../domain/pedeon_settings.dart';
import 'pedeon_settings_view_model.dart';
import 'pedeon_orders_panel.dart';
import 'modifier_group_editor_dialog.dart';
import 'delivery_zone_editor_dialog.dart';
import 'store_hours_card.dart';
import 'delivery_operation_card.dart';

class PedeOnSettingsScreen extends StatefulWidget {
  const PedeOnSettingsScreen({
    super.key,
    required this.session,
    this.viewModel,
  });

  final Session session;
  final PedeOnSettingsViewModel? viewModel;

  @override
  State<PedeOnSettingsScreen> createState() => _PedeOnSettingsScreenState();
}

class _PedeOnSettingsScreenState extends State<PedeOnSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final PedeOnSettingsViewModel _viewModel;
  late final TabController _tabController;
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _description = TextEditingController();
  final _minimumOrder = TextEditingController();
  final _manualPixKey = TextEditingController();
  final _manualPixRecipient = TextEditingController();
  final _manualPixInstructions = TextEditingController();
  final _infinitePayHandle = TextEditingController();
  final _catalogSearch = TextEditingController();
  int? _loadedStoreId;
  PedeOnStoreSettings? _storeDraft;
  PedeOnManualPixSettings? _manualPixDraft;
  PedeOnInfinitePaySettings? _infinitePayDraft;
  PedeOnDeliveryCardSettings? _deliveryCardDraft;
  PedeOnPickupPaymentSettings? _pickupPaymentDraft;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _viewModel =
        widget.viewModel ??
        PedeOnSettingsViewModel(HttpPedeOnRepository(widget.session));
    _viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _tabController.dispose();
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    _minimumOrder.dispose();
    _manualPixKey.dispose();
    _manualPixRecipient.dispose();
    _manualPixInstructions.dispose();
    _infinitePayHandle.dispose();
    _catalogSearch.dispose();
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _viewModel.load();
    if (_viewModel.settings != null) {
      await Future.wait([
        _viewModel.loadCatalog(page: 1),
        _viewModel.loadOrders(page: 1),
      ]);
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final settings = _viewModel.settings;
    if (settings != null && _loadedStoreId != settings.store.id) {
      _syncDrafts(settings);
    }
    setState(() {});
  }

  void _syncDrafts(PedeOnSettings settings) {
    _loadedStoreId = settings.store.id;
    _storeDraft = settings.store;
    _manualPixDraft = settings.manualPix;
    _infinitePayDraft = settings.infinitePay;
    _deliveryCardDraft = settings.deliveryCard;
    _pickupPaymentDraft = settings.pickupPayment;
    _name.text = settings.store.displayName;
    _slug.text = settings.store.publicSlug;
    _description.text = settings.store.description;
    _minimumOrder.text = settings.store.minimumOrderAmount.toStringAsFixed(2);
    _manualPixKey.text = settings.manualPix.pixKey;
    _manualPixRecipient.text = settings.manualPix.recipientName;
    _manualPixInstructions.text = settings.manualPix.instructions;
    _infinitePayHandle.text = settings.infinitePay.handle;
  }

  @override
  Widget build(BuildContext context) {
    if (_viewModel.loading && _viewModel.settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.settings == null) {
      return _ErrorState(message: _viewModel.error, onRetry: _loadAll);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: _HeroHeader(
                store: _storeDraft!,
                onConfigure: () => _tabController.animateTo(1),
                onRefresh: _loadAll,
                refreshing: _viewModel.loading,
              ),
            ),
            SliverToBoxAdapter(
              child: _PedeOnTabs(
                controller: _tabController,
                experienceMode: _storeDraft!.experienceMode,
              ),
            ),
            if (_viewModel.error != null)
              SliverToBoxAdapter(
                child: _NoticeBanner(
                  icon: Icons.error_outline,
                  color: const Color(0xFFB42318),
                  message: _viewModel.error!,
                ),
              ),
            if (_viewModel.successMessage != null)
              SliverToBoxAdapter(
                child: _NoticeBanner(
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF067647),
                  message: _viewModel.successMessage!,
                ),
              ),
          ],
          body: AnimatedBuilder(
            animation: _tabController,
            builder: (context, child) => IndexedStack(
              index: _tabController.index,
              children: [
                PedeOnOrdersPanel(viewModel: _viewModel),
                _buildStoreTab(),
                _buildCatalogTab(),
                _buildPaymentsTab(),
                _buildDeliveryTab(),
                _buildTerminalsTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreTab() => _PagePadding(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Os cartões possuem seletores com textos operacionais extensos.
        // Só os colocamos lado a lado quando cada coluna mantém largura útil
        // suficiente, inclusive com zoom do navegador.
        final wide = constraints.maxWidth >= 1280;
        final form = _SectionCard(
          title: 'Identidade da loja',
          subtitle: 'Como sua marca aparece para quem faz o pedido.',
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome público'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _slug,
                decoration: const InputDecoration(
                  labelText: 'Subdomínio público',
                  suffixText: '.lyncar.com.br/cardapio',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Apresentação da loja',
                ),
              ),
            ],
          ),
        );
        final operation = _SectionCard(
          title: 'Operação dos pedidos',
          subtitle: 'Controle quando e como os pedidos podem entrar.',
          icon: Icons.tune_outlined,
          child: Column(
            children: [
              _SwitchLine(
                title: 'Publicar cardápio',
                subtitle: 'A loja poderá ser encontrada pelo endereço público.',
                value: _storeDraft!.active,
                onChanged: (value) => setState(() {
                  _storeDraft = _storeDraft!.copyWith(active: value);
                }),
              ),
              _SwitchLine(
                title: 'Receber pedidos agora',
                subtitle: 'Pode ser desligado sem tirar o cardápio do ar.',
                value: _storeDraft!.acceptingOrders,
                onChanged: (value) => setState(() {
                  _storeDraft = _storeDraft!.copyWith(acceptingOrders: value);
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _storeDraft!.acceptanceMode,
                decoration: const InputDecoration(
                  labelText: 'Aceite do pedido',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Manual pela equipe'),
                  ),
                  DropdownMenuItem(
                    value: 'automatic',
                    child: Text('Automático'),
                  ),
                  DropdownMenuItem(
                    value: 'mixed',
                    child: Text('Misto por pagamento'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _storeDraft = _storeDraft!.copyWith(acceptanceMode: value);
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _storeDraft!.inventoryPolicy,
                decoration: const InputDecoration(
                  labelText: 'Comportamento quando faltar estoque',
                  helperText:
                      'Em alimentação, avisar e permitir evita perder pedidos por ficha técnica desatualizada.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'warn_allow',
                    child: Text('Avisar e permitir (recomendado)'),
                  ),
                  DropdownMenuItem(
                    value: 'strict_block',
                    child: Text('Bloquear o pedido'),
                  ),
                  DropdownMenuItem(
                    value: 'untracked',
                    child: Text('Não controlar estoque pelo PedeOn'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _storeDraft = _storeDraft!.copyWith(inventoryPolicy: value);
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _storeDraft!.productionPrintPolicy,
                decoration: InputDecoration(
                  labelText: _storeDraft!.experienceMode == 'food_service'
                      ? 'Impressão para produção'
                      : 'Impressão para separação',
                  helperText:
                      'Imprimir é opcional e nunca é ativado só por publicar a loja.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'disabled',
                    child: Text('Não imprimir'),
                  ),
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Imprimir somente quando solicitado'),
                  ),
                  DropdownMenuItem(
                    value: 'automatic',
                    child: Text('Imprimir automaticamente'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _storeDraft = _storeDraft!.copyWith(
                    productionPrintPolicy: value,
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minimumOrder,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Pedido mínimo',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  children: [
                    FilterChip(
                      label: const Text('Retirada'),
                      selected: _storeDraft!.fulfillmentOptions.contains(
                        'pickup',
                      ),
                      onSelected: (value) =>
                          _toggleFulfillment('pickup', value),
                    ),
                    FilterChip(
                      label: const Text('Entrega'),
                      selected: _storeDraft!.fulfillmentOptions.contains(
                        'delivery',
                      ),
                      onSelected: (value) =>
                          _toggleFulfillment('delivery', value),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        return Column(
          children: [
            _ExperienceModeCard(
              store: _storeDraft!,
              onChanged: (mode, segment, fulfillment) => setState(() {
                _storeDraft = _storeDraft!.copyWith(
                  experienceMode: mode,
                  businessSegment: segment,
                  defaultFulfillmentMode: fulfillment,
                );
              }),
            ),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: form),
                  const SizedBox(width: 20),
                  Expanded(child: operation),
                ],
              )
            else ...[
              form,
              const SizedBox(height: 16),
              operation,
            ],
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Horários de atendimento',
              subtitle:
                  'Defina quando o estabelecimento recebe pedidos. Esta regra vale para retirada e entrega.',
              icon: Icons.schedule_outlined,
              child: StoreHoursCard(
                key: ValueKey(
                  'hours-${_viewModel.settings!.deliveryOperation.hashCode}',
                ),
                initialValue: _viewModel.settings!.deliveryOperation,
                saving: _viewModel.saving,
                onSave: _viewModel.saveDeliveryOperation,
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Estações operacionais',
              subtitle:
                  'Direcione cada item para cozinha, bar, confeitaria, separação ou expedição.',
              icon: Icons.account_tree_outlined,
              child: Column(
                children: [
                  for (final station
                      in _viewModel.settings!.fulfillmentStations) ...[
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Icon(
                            station.stationType == 'picking'
                                ? Icons.inventory_2_outlined
                                : station.stationType == 'expedition'
                                ? Icons.local_shipping_outlined
                                : Icons.soup_kitchen_outlined,
                          ),
                        ),
                        title: Text(station.name),
                        subtitle: Text(
                          '${station.code} • ${_stationTypeLabel(station.stationType)}${station.active ? '' : ' • Inativa'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Editar estação',
                          onPressed: () => _showStationEditor(station),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _viewModel.saving
                          ? null
                          : () => _showStationEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('Nova estação'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _viewModel.saving ? null : _saveStore,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar configurações'),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildPaymentsTab() => _PagePadding(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _SectionCard(
            title: 'Pix manual',
            subtitle: 'Você informa sua chave e confirma o recebimento.',
            icon: Icons.pix,
            badge: 'Conferência manual',
            child: Column(
              children: [
                _SwitchLine(
                  title: 'Oferecer Pix manual',
                  subtitle: 'Nunca será marcado como pago automaticamente.',
                  value: _manualPixDraft!.enabled,
                  onChanged: (value) => setState(() {
                    _manualPixDraft = _manualPixDraft!.copyWith(enabled: value);
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Disponível na retirada',
                  subtitle: 'Mostra esta forma ao cliente que vai buscar.',
                  value: _manualPixDraft!.pickupEnabled,
                  onChanged: (value) => setState(() {
                    _manualPixDraft = _manualPixDraft!.copyWith(
                      pickupEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Disponível na entrega',
                  subtitle: 'Mostra esta forma ao cliente que recebe em casa.',
                  value: _manualPixDraft!.deliveryEnabled,
                  onChanged: (value) => setState(() {
                    _manualPixDraft = _manualPixDraft!.copyWith(
                      deliveryEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _manualPixDraft!.keyType,
                  decoration: const InputDecoration(labelText: 'Tipo da chave'),
                  items: const [
                    DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                    DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                    DropdownMenuItem(value: 'email', child: Text('E-mail')),
                    DropdownMenuItem(value: 'phone', child: Text('Telefone')),
                    DropdownMenuItem(
                      value: 'random',
                      child: Text('Chave aleatória'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _manualPixDraft = _manualPixDraft!.copyWith(keyType: value);
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _manualPixKey,
                  decoration: const InputDecoration(labelText: 'Chave Pix'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _manualPixRecipient,
                  decoration: const InputDecoration(
                    labelText: 'Nome do recebedor',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _manualPixInstructions,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Orientação ao cliente (opcional)',
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _viewModel.saving ? null : _saveManualPix,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar Pix manual'),
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Pix InfinitePay',
            subtitle: 'Confirmação automática pelo provedor de pagamento.',
            icon: Icons.bolt_outlined,
            badge: 'Automático',
            child: Column(
              children: [
                _SwitchLine(
                  title: 'Ativar InfinitePay',
                  subtitle: 'O pedido aguarda a confirmação real do pagamento.',
                  value: _infinitePayDraft!.enabled,
                  onChanged: (value) => setState(() {
                    _infinitePayDraft = _infinitePayDraft!.copyWith(
                      enabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Disponível na retirada',
                  subtitle: 'Mostra o Pix online ao cliente que vai buscar.',
                  value: _infinitePayDraft!.pickupEnabled,
                  onChanged: (value) => setState(() {
                    _infinitePayDraft = _infinitePayDraft!.copyWith(
                      pickupEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Disponível na entrega',
                  subtitle:
                      'Mostra o Pix online ao cliente que recebe em casa.',
                  value: _infinitePayDraft!.deliveryEnabled,
                  onChanged: (value) => setState(() {
                    _infinitePayDraft = _infinitePayDraft!.copyWith(
                      deliveryEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _infinitePayHandle,
                  decoration: const InputDecoration(
                    labelText: 'Identificador InfinitePay',
                    hintText: 'sua-loja',
                  ),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Aceitar após pagamento',
                  subtitle:
                      'Depois da confirmação, envia o pedido para produção.',
                  value: _infinitePayDraft!.autoAcceptAfterConfirmation,
                  onChanged: (value) => setState(() {
                    _infinitePayDraft = _infinitePayDraft!.copyWith(
                      autoAcceptAfterConfirmation: value,
                    );
                  }),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _viewModel.saving ? null : _saveInfinitePay,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar InfinitePay'),
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Pagamento na retirada',
            subtitle: 'O cliente escolhe a forma e paga ao retirar no balcão.',
            icon: Icons.storefront_outlined,
            badge: 'Somente retirada',
            child: Column(
              children: [
                _SwitchLine(
                  title: 'Permitir pagar no local',
                  subtitle: 'Exibe a escolha apenas para pedidos de retirada.',
                  value: _pickupPaymentDraft!.enabled,
                  onChanged: (value) => setState(() {
                    _pickupPaymentDraft = _pickupPaymentDraft!.copyWith(
                      enabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Formas aceitas no local',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final option in const <(String, String)>[
                  ('cash', 'Dinheiro'),
                  ('pix', 'Pix'),
                  ('credit_card', 'Cartão de crédito'),
                  ('debit_card', 'Cartão de débito'),
                ])
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.$2),
                      value: _pickupPaymentDraft!.acceptedMethods.contains(
                        option.$1,
                      ),
                      onChanged: (value) => setState(() {
                        final methods = {
                          ..._pickupPaymentDraft!.acceptedMethods,
                        };
                        if (value == true) {
                          methods.add(option.$1);
                        } else if (methods.length > 1) {
                          methods.remove(option.$1);
                        }
                        _pickupPaymentDraft = _pickupPaymentDraft!.copyWith(
                          acceptedMethods: methods.toList(),
                        );
                      }),
                    ),
                  ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _viewModel.saving ? null : _savePickupPayment,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar formas locais'),
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Pagamento na entrega',
            subtitle: 'Escolha as formas que o cliente poderá usar ao receber.',
            icon: Icons.credit_card_outlined,
            badge: 'Somente entrega',
            child: Column(
              children: [
                _SwitchLine(
                  title: 'Aceitar dinheiro na entrega',
                  subtitle: 'O cliente informa o valor para calcular o troco.',
                  value: _deliveryCardDraft!.cashEnabled,
                  onChanged: (value) => setState(() {
                    _deliveryCardDraft = _deliveryCardDraft!.copyWith(
                      cashEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Aceitar Pix na entrega',
                  subtitle: 'O cliente paga por Pix diretamente ao receber.',
                  value: _deliveryCardDraft!.pixEnabled,
                  onChanged: (value) => setState(() {
                    _deliveryCardDraft = _deliveryCardDraft!.copyWith(
                      pixEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Aceitar crédito na entrega',
                  subtitle: 'O cliente escolhe crédito e paga ao receber.',
                  value: _deliveryCardDraft!.creditEnabled,
                  onChanged: (value) => setState(() {
                    _deliveryCardDraft = _deliveryCardDraft!.copyWith(
                      creditEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _SwitchLine(
                  title: 'Aceitar débito na entrega',
                  subtitle: 'O cliente escolhe débito e paga ao receber.',
                  value: _deliveryCardDraft!.debitEnabled,
                  onChanged: (value) => setState(() {
                    _deliveryCardDraft = _deliveryCardDraft!.copyWith(
                      debitEnabled: value,
                    );
                  }),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _viewModel.saving ? null : _saveDeliveryCard,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar pagamentos da entrega'),
                  ),
                ),
              ],
            ),
          ),
        ];
        final width = constraints.maxWidth >= 980
            ? (constraints.maxWidth - 20) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    ),
  );

  Widget _buildTerminalsTab() => _PagePadding(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoStrip(
          title: 'Você decide onde o PedeOn aparece',
          description:
              'Um mercado pode deixar um único PDV responsável ou liberar vários terminais. Cada PDV recebe somente as ações marcadas abaixo.',
        ),
        const SizedBox(height: 18),
        if (_viewModel.settings!.terminals.isEmpty)
          const _EmptyTerminals()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 18) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final terminal in _viewModel.settings!.terminals)
                    SizedBox(
                      width: width,
                      child: _TerminalCard(
                        terminal: terminal,
                        saving: _viewModel.saving,
                        onSave: _viewModel.saveTerminal,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );

  Widget _buildDeliveryTab() => _PagePadding(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: 'Configuração de entrega',
          subtitle:
              'Configure cobertura, taxas, prazo e funcionamento em um único fluxo.',
          icon: Icons.local_shipping_outlined,
          badge: '${_viewModel.settings!.deliveryZones.length} configurada(s)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeliveryOperationCard(
                key: ValueKey(_viewModel.settings!.deliveryOperation.hashCode),
                initialValue: _viewModel.settings!.deliveryOperation,
                saving: _viewModel.saving,
                onSave: _viewModel.saveDeliveryOperation,
              ),
              const Divider(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final addButton = FilledButton.icon(
                    onPressed:
                        _viewModel.saving ||
                            _viewModel
                                    .settings!
                                    .deliveryOperation
                                    .pricingMode !=
                                'zones'
                        ? null
                        : () => _editDeliveryZone(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nova área'),
                  );
                  const heading = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(child: Icon(Icons.map_outlined)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cobertura e taxas',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Defina onde a empresa entrega e teste os endereços antes de publicar.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading,
                        const SizedBox(height: 12),
                        addButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Expanded(child: heading),
                      const SizedBox(width: 16),
                      addButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_viewModel.settings!.deliveryOperation.pricingMode == 'zones')
                const _InfoStrip(
                  title: 'Cobrança automática por endereço',
                  description:
                      'Cadastre por CEP ou bairro. Quando mais de uma regra coincidir, o CEP mais específico prevalece.',
                ),
              if (_viewModel.settings!.deliveryOperation.pricingMode == 'zones')
                const SizedBox(height: 16),
              if (_viewModel.settings!.deliveryOperation.pricingMode == 'fixed')
                const _InfoStrip(
                  title: 'Taxa única ativa',
                  description:
                      'A mesma taxa será aplicada a todos os endereços aceitos. As áreas abaixo ficam preservadas, mas não participam do cálculo.',
                )
              else ...[
                if (_viewModel.settings!.deliveryZones.isEmpty)
                  const _EmptyDeliveryZones()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 980 ? 2 : 1;
                      final width = columns == 2
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final zone in _viewModel.settings!.deliveryZones)
                            SizedBox(
                              width: width,
                              child: _DeliveryZoneCard(
                                zone: zone,
                                saving: _viewModel.saving,
                                onEdit: () => _editDeliveryZone(zone),
                                onDelete: () => _deleteDeliveryZone(zone),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildCatalogTab() => _PagePadding(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Catálogo central do PedeOn',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Os produtos vêm do estoque. Em cada item você define separadamente se ele aparece no Online e no Salão.',
          style: TextStyle(color: Color(0xFF667085)),
        ),
        const SizedBox(height: 14),
        _CatalogToolbar(
          controller: _catalogSearch,
          total: _viewModel.catalog?.total ?? 0,
          loading: _viewModel.catalogLoading,
          onSearch: () => _viewModel.loadCatalog(
            search: _catalogSearch.text.trim(),
            page: 1,
          ),
          onCreateCategory: _showCreateCategory,
        ),
        const SizedBox(height: 18),
        _CategoryStrip(
          categories: _viewModel.catalog?.categories ?? const [],
          saving: _viewModel.saving,
          onReorder: _viewModel.reorderCategories,
          onDelete: _confirmDeleteCategory,
          onEdit: _showEditCategory,
        ),
        const SizedBox(height: 18),
        if (_storeDraft!.experienceMode == 'food_service') ...[
          _ModifierGroupsCard(
            groups: _viewModel.catalog?.modifierGroups ?? const [],
            onCreate: () => _showModifierGroupEditor(),
            onEdit: _showModifierGroupEditor,
            onDelete: _confirmDeleteModifierGroup,
          ),
          const SizedBox(height: 18),
        ],
        if (_viewModel.catalogLoading && _viewModel.catalog == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if ((_viewModel.catalog?.items ?? const []).isEmpty)
          const _EmptyCatalog()
        else
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _viewModel.catalog!.items.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: constraints.maxWidth < 650
                    ? constraints.maxWidth
                    : 390,
                mainAxisExtent: 430,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final product = _viewModel.catalog!.items[index];
                return _CatalogProductCard(
                  product: product,
                  saving: _viewModel.saving,
                  onEdit: () => _showProductEditor(product),
                  onToggleChannel: (channel, value) =>
                      _toggleProductChannel(product, channel, value),
                );
              },
            ),
          ),
        if (_viewModel.catalog != null) ...[
          const SizedBox(height: 20),
          _CatalogPagination(
            page: _viewModel.catalog!.page,
            totalPages: _viewModel.catalog!.totalPages,
            onPage: (page) => _viewModel.loadCatalog(page: page),
          ),
        ],
      ],
    ),
  );

  Future<void> _showCreateCategory() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final selectedProducts = <int>{};
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova categoria'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da categoria',
                ),
              ),
              if (_viewModel.catalog?.items.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Adicionar produtos agora',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final product in _viewModel.catalog!.items)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedProducts.contains(product.productId),
                          title: Text(product.productName),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                selectedProducts.add(product.productId);
                              } else {
                                selectedProducts.remove(product.productId);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().length < 2) return;
              final ok = await _viewModel.createCategoryWithProducts(
                name.text.trim(),
                description.text.trim(),
                (_viewModel.catalog?.items ?? const [])
                    .where((item) => selectedProducts.contains(item.productId))
                    .toList(),
                channel: 'shared',
              );
              if (context.mounted) Navigator.pop(context, ok);
            },
            child: const Text('Criar categoria'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _showEditCategory(PedeOnCategory category) async {
    final name = TextEditingController(text: category.name);
    final description = TextEditingController(text: category.description);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar categoria'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da categoria',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().length < 2) return;
              final ok = await _viewModel.updateCategory(
                category.copyWith(
                  name: name.text.trim(),
                  description: description.text.trim(),
                ),
              );
              if (context.mounted) Navigator.pop(context, ok);
            },
            child: const Text('Salvar categoria'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _confirmDeleteCategory(PedeOnCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir ${category.name}?'),
        content: const Text(
          'Os produtos não serão excluídos; apenas ficarão sem categoria no cardápio.',
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
    if (confirmed == true) await _viewModel.deleteCategory(category.id);
  }

  Future<void> _showProductEditor(PedeOnCatalogProduct product) async {
    final edited = await showDialog<PedeOnCatalogProduct>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProductEditorDialog(
        product: product,
        categories: _viewModel.catalog?.categories ?? const [],
        modifierGroups: _viewModel.catalog?.modifierGroups ?? const [],
        stations: _viewModel.settings?.fulfillmentStations ?? const [],
      ),
    );
    if (edited != null) await _viewModel.savePublication(edited);
  }

  Future<void> _toggleProductChannel(
    PedeOnCatalogProduct product,
    String channel,
    bool value,
  ) async {
    final published = {...product.publishedChannels};
    final available = {...product.availableChannels};
    final legacyOnline = product.published && product.publishedChannels.isEmpty;
    if (legacyOnline) {
      published.add('pedeon_online');
      available.add('pedeon_online');
    }
    if (value) {
      published.add(channel);
      available.add(channel);
    } else {
      published.remove(channel);
      available.remove(channel);
    }
    await _viewModel.savePublication(
      product.copyWith(
        published: published.contains('pedeon_online'),
        available: available.isNotEmpty,
        publishedChannels: published.toList(),
        availableChannels: available.toList(),
      ),
    );
  }

  Future<void> _showStationEditor([PedeOnFulfillmentStation? station]) async {
    final edited = await showDialog<PedeOnFulfillmentStation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StationEditorDialog(station: station),
    );
    if (edited != null) await _viewModel.saveStation(edited);
  }

  Future<void> _showModifierGroupEditor([PedeOnModifierGroup? group]) async {
    final edited = await showModifierGroupEditor(
      context,
      group: group,
      products: _viewModel.catalog?.items ?? const [],
      searchProducts: _viewModel.searchCatalogProducts,
    );
    if (edited != null) {
      await _viewModel.saveModifierGroup(edited.copyWith(channel: 'shared'));
    }
  }

  Future<void> _confirmDeleteModifierGroup(PedeOnModifierGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir ${group.name}?'),
        content: const Text(
          'O grupo deixará de aparecer em todos os produtos vinculados.',
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
    if (confirmed == true && group.id != null) {
      await _viewModel.deleteModifierGroup(group.id!);
    }
  }

  void _toggleFulfillment(String option, bool selected) {
    final options = [..._storeDraft!.fulfillmentOptions];
    if (selected) {
      if (!options.contains(option)) options.add(option);
    } else if (options.length > 1) {
      options.remove(option);
    }
    setState(
      () => _storeDraft = _storeDraft!.copyWith(fulfillmentOptions: options),
    );
  }

  Future<void> _saveStore() async {
    final minimum =
        double.tryParse(_minimumOrder.text.replaceAll(',', '.')) ?? 0;
    final value = _storeDraft!.copyWith(
      displayName: _name.text.trim(),
      publicSlug: _slug.text.trim().toLowerCase(),
      description: _description.text.trim(),
      minimumOrderAmount: minimum,
    );
    if (await _viewModel.saveStore(value)) _loadedStoreId = null;
  }

  Future<void> _saveManualPix() async {
    final value = _manualPixDraft!.copyWith(
      pixKey: _manualPixKey.text,
      recipientName: _manualPixRecipient.text,
      instructions: _manualPixInstructions.text,
    );
    if (await _viewModel.saveManualPix(value)) _loadedStoreId = null;
  }

  Future<void> _saveInfinitePay() async {
    final value = _infinitePayDraft!.copyWith(handle: _infinitePayHandle.text);
    if (await _viewModel.saveInfinitePay(value)) _loadedStoreId = null;
  }

  Future<void> _saveDeliveryCard() async {
    if (await _viewModel.saveDeliveryCard(_deliveryCardDraft!)) {
      _loadedStoreId = null;
    }
  }

  Future<void> _savePickupPayment() async {
    if (await _viewModel.savePickupPayment(_pickupPaymentDraft!)) {
      _loadedStoreId = null;
    }
  }

  Future<void> _editDeliveryZone([PedeOnDeliveryZone? zone]) async {
    final result = await showDialog<PedeOnDeliveryZone>(
      context: context,
      builder: (context) => DeliveryZoneEditorDialog(zone: zone),
    );
    if (result != null) await _viewModel.saveDeliveryZone(result);
  }

  Future<void> _deleteDeliveryZone(PedeOnDeliveryZone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir área de entrega?'),
        content: Text(
          '${zone.name} deixará de aceitar novos endereços imediatamente.',
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
    if (confirmed == true && zone.id != null) {
      await _viewModel.deleteDeliveryZone(zone.id!);
    }
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.store,
    required this.onConfigure,
    required this.onRefresh,
    required this.refreshing,
  });
  final PedeOnStoreSettings store;
  final VoidCallback onConfigure;
  final VoidCallback onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF26D9B0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.shopping_bag_outlined,
            color: Color(0xFF062436),
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PedeOn',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'PedeOn by Lyncar  •  ${store.displayName}',
                style: const TextStyle(color: Color(0xFFC7DCE7), fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
    final controls = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('pedeon-configure-experience'),
          onPressed: onConfigure,
          icon: Icon(
            store.experienceMode == 'food_service'
                ? Icons.restaurant_menu_rounded
                : Icons.shopping_bag_outlined,
          ),
          label: Text(
            store.experienceMode == 'food_service'
                ? 'Tipo: Cardápio / Alimentação'
                : 'Tipo: Loja online',
          ),
        ),
        _StatusPill(active: store.active, accepting: store.acceptingOrders),
        IconButton.filledTonal(
          tooltip: 'Atualizar PedeOn',
          onPressed: refreshing ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF071A2D), Color(0xFF0A4962)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [brand, const SizedBox(height: 16), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: brand),
              const SizedBox(width: 20),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.accepting});
  final bool active;
  final bool accepting;
  @override
  Widget build(BuildContext context) {
    final online = active && accepting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: online ? const Color(0xFFDCFCE7) : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 9,
            color: online ? const Color(0xFF16A34A) : const Color(0xFF667085),
          ),
          const SizedBox(width: 7),
          Text(
            online ? 'Recebendo pedidos' : 'Loja pausada',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ExperienceModeCard extends StatelessWidget {
  const _ExperienceModeCard({required this.store, required this.onChanged});

  final PedeOnStoreSettings store;
  final void Function(String mode, String segment, String fulfillment)
  onChanged;

  static const _foodSegments = <String, String>{
    'restaurant': 'Restaurante',
    'burger': 'Hamburgueria',
    'bakery': 'Padaria e confeitaria',
    'market': 'Mercado',
    'other': 'Outro negócio de alimentação',
  };
  static const _retailSegments = <String, String>{
    'fashion': 'Moda e roupas',
    'accessories': 'Acessórios',
    'automotive': 'Autopeças e baterias',
    'market': 'Mercado e conveniência',
    'services': 'Serviços',
    'other': 'Outro tipo de loja',
  };

  @override
  Widget build(BuildContext context) {
    final food = store.experienceMode == 'food_service';
    final segments = food ? _foodSegments : _retailSegments;
    final segment = segments.containsKey(store.businessSegment)
        ? store.businessSegment
        : 'other';
    return _SectionCard(
      title: 'Como seus clientes compram?',
      subtitle:
          'Isso organiza a experiência e libera somente as configurações adequadas. Pode ser alterado depois sem apagar produtos ou pedidos.',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _ExperienceChoice(
                  selected: food,
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Cardápio / Alimentação',
                  description:
                      'Personalizações, adicionais, preparo, salão e cozinha quando habilitados.',
                  onTap: () =>
                      onChanged('food_service', 'other', 'preparation'),
                ),
                _ExperienceChoice(
                  selected: !food,
                  icon: Icons.shopping_bag_outlined,
                  title: 'Loja online',
                  description:
                      'Vitrine, variações, separação e entrega sem telas de cozinha.',
                  onTap: () => onChanged('retail', 'other', 'picking'),
                ),
              ];
              if (constraints.maxWidth >= 760) {
                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 14),
                    Expanded(child: cards[1]),
                  ],
                );
              }
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('${store.experienceMode}:$segment'),
            initialValue: segment,
            decoration: const InputDecoration(
              labelText: 'Segmento da empresa',
              helperText:
                  'O segmento sugere uma configuração inicial; não limita os recursos contratados.',
            ),
            items: [
              for (final entry in segments.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(
                  store.experienceMode,
                  value,
                  food ? 'preparation' : 'picking',
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ExperienceChoice extends StatelessWidget {
  const _ExperienceChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE6F7F5) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? const Color(0xFF087B75) : const Color(0xFFD0D5DD),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF087B75), size: 30),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle, color: Color(0xFF087B75)),
        ],
      ),
    ),
  );
}

class _PedeOnTabs extends StatelessWidget {
  const _PedeOnTabs({required this.controller, required this.experienceMode});
  final TabController controller;
  final String experienceMode;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: EdgeInsets.symmetric(horizontal: 20),
      tabs: [
        const Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Pedidos'),
        const Tab(
          icon: Icon(Icons.storefront_outlined),
          text: 'Configuração da loja',
        ),
        Tab(
          icon: Icon(
            experienceMode == 'food_service'
                ? Icons.restaurant_menu_outlined
                : Icons.inventory_2_outlined,
          ),
          text: experienceMode == 'food_service' ? 'Cardápio' : 'Produtos',
        ),
        const Tab(
          icon: Icon(Icons.account_balance_wallet_outlined),
          text: 'Pagamentos',
        ),
        const Tab(icon: Icon(Icons.delivery_dining_outlined), text: 'Entrega'),
        const Tab(
          icon: Icon(Icons.point_of_sale_outlined),
          text: 'PDVs autorizados',
        ),
      ],
    ),
  );
}

class _PagePadding extends StatelessWidget {
  const _PagePadding({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: true,
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: child,
      ),
    ),
  );
}

class _DeliveryZoneCard extends StatelessWidget {
  const _DeliveryZoneCard({
    required this.zone,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
  });

  final PedeOnDeliveryZone zone;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final location = switch (zone.matchType) {
      'postal_code_prefix' => 'CEP iniciado por ${zone.postalCodePrefix}',
      'radius' => 'Raio de ${zone.radiusKm?.toStringAsFixed(1) ?? '-'} km',
      _ => 'Bairro ${zone.neighborhood}',
    };
    final place = [
      zone.city,
      zone.state,
    ].where((value) => value.trim().isNotEmpty).join(' / ');
    final estimate = zone.estimatedMinutesMin == null
        ? 'Prazo não informado'
        : zone.estimatedMinutesMax == null ||
              zone.estimatedMinutesMax == zone.estimatedMinutesMin
        ? '${zone.estimatedMinutesMin} min'
        : '${zone.estimatedMinutesMin}–${zone.estimatedMinutesMax} min';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: zone.active ? Colors.white : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E1EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: zone.active
                    ? const Color(0xFFE0F7F3)
                    : const Color(0xFFE7E9ED),
                child: Icon(
                  Icons.location_on_outlined,
                  color: zone.active
                      ? const Color(0xFF087B75)
                      : const Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('$location${place.isEmpty ? '' : ' • $place'}'),
                  ],
                ),
              ),
              Chip(label: Text(zone.active ? 'Ativa' : 'Pausada')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ZoneMetric(label: 'Taxa', value: _deliveryMoney(zone.feeAmount)),
              _ZoneMetric(
                label: 'Pedido mínimo',
                value: _deliveryMoney(zone.minimumOrderAmount),
              ),
              if (zone.freeDeliveryThreshold != null)
                _ZoneMetric(
                  label: 'Grátis a partir de',
                  value: _deliveryMoney(zone.freeDeliveryThreshold!),
                ),
              _ZoneMetric(label: 'Estimativa', value: estimate),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Excluir área',
                onPressed: saving ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: saving ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoneMetric extends StatelessWidget {
  const _ZoneMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F7FB),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$label: $value'),
  );
}

String _deliveryMoney(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

class _EmptyDeliveryZones extends StatelessWidget {
  const _EmptyDeliveryZones();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD7E1EC)),
    ),
    child: const Column(
      children: [
        Icon(Icons.map_outlined, size: 42, color: Color(0xFF667085)),
        SizedBox(height: 10),
        Text(
          'Nenhuma área configurada',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Enquanto não houver áreas, a entrega antiga continua sem taxa. Cadastre a primeira área para começar a validar o alcance.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _CatalogToolbar extends StatelessWidget {
  const _CatalogToolbar({
    required this.controller,
    required this.total,
    required this.loading,
    required this.onSearch,
    required this.onCreateCategory,
  });
  final TextEditingController controller;
  final int total;
  final bool loading;
  final VoidCallback onSearch;
  final VoidCallback onCreateCategory;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        controller: controller,
        onSubmitted: (_) => onSearch(),
        decoration: InputDecoration(
          labelText: 'Buscar produto no estoque',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            onPressed: loading ? null : onSearch,
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      );
      final actions = Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text('$total produtos'),
          ),
          FilledButton.icon(
            onPressed: onCreateCategory,
            icon: const Icon(Icons.add),
            label: const Text('Nova categoria'),
          ),
        ],
      );
      if (constraints.maxWidth < 760) {
        return Column(
          children: [
            search,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 14),
          Flexible(child: actions),
        ],
      );
    },
  );
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.saving,
    required this.onReorder,
    required this.onDelete,
    required this.onEdit,
  });
  final List<PedeOnCategory> categories;
  final bool saving;
  final ReorderCallback onReorder;
  final ValueChanged<PedeOnCategory> onDelete;
  final ValueChanged<PedeOnCategory> onEdit;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDCE6EF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.category_outlined, color: Color(0xFF087B75)),
            SizedBox(width: 9),
            Text(
              'Categorias do cardápio',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          const Text(
            'Crie categorias como Pães, Bebidas ou Combos para organizar a loja.',
            style: TextStyle(color: Color(0xFF667085)),
          )
        else ...[
          const Text(
            'Arraste pelo puxador para definir a ordem exibida na loja.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 10),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            onReorderItem: saving ? (_, _) {} : onReorder,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Container(
                key: ValueKey(category.id),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDCE6EF)),
                ),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: index,
                    enabled: !saving,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_indicator),
                      ),
                    ),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Posição ${index + 1} no cardápio'),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Editar categoria',
                        onPressed: saving ? null : () => onEdit(category),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Excluir categoria',
                        onPressed: saving ? null : () => onDelete(category),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}

class _CatalogProductCard extends StatelessWidget {
  const _CatalogProductCard({
    required this.product,
    required this.saving,
    required this.onEdit,
    required this.onToggleChannel,
  });
  final PedeOnCatalogProduct product;
  final bool saving;
  final VoidCallback onEdit;
  final void Function(String channel, bool value) onToggleChannel;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: product.published
            ? const Color(0xFF80DCC8)
            : const Color(0xFFDCE6EF),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A102A43),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: product.effectiveImage.isEmpty
              ? const ColoredBox(
                  color: Color(0xFFEAF2F8),
                  child: Icon(
                    Icons.fastfood_outlined,
                    size: 42,
                    color: Color(0xFF7890A5),
                  ),
                )
              : Image.network(
                  product.effectiveImage,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFEAF2F8),
                    child: Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.effectiveName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        _ChannelSwitch(
                          label: 'Online',
                          value: product.publishedChannels.isEmpty
                              ? product.published
                              : product.publishedChannels.contains(
                                  'pedeon_online',
                                ),
                          onChanged: saving
                              ? null
                              : (value) =>
                                    onToggleChannel('pedeon_online', value),
                        ),
                        _ChannelSwitch(
                          label: 'Salão',
                          value: product.publishedChannels.contains(
                            'onsite_qr',
                          ),
                          onChanged: saving
                              ? null
                              : (value) => onToggleChannel('onsite_qr', value),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  product.internalCode.isEmpty
                      ? 'Produto #${product.productId}'
                      : product.internalCode,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (product.enabledChannels.contains('pedeon_online'))
                      const _ChannelBadge(label: 'Online', icon: Icons.public),
                    if (product.enabledChannels.contains('onsite_qr'))
                      const _ChannelBadge(
                        label: 'Salão / QR',
                        icon: Icons.table_restaurant,
                      ),
                    if (product.enabledChannels.isEmpty)
                      const _ChannelBadge(
                        label: 'Nenhum canal',
                        icon: Icons.visibility_off_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _money(product.effectivePrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF087B75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SmallStatus(
                      label: product.available ? 'Disponível' : 'Pausado',
                      positive: product.available,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Estoque: ${product.stockQuantity.toStringAsFixed(2)} ${product.unit}',
                  style: const TextStyle(color: Color(0xFF475467)),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : onEdit,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Configurar produto'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChannelSwitch extends StatelessWidget {
  const _ChannelSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
      Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ],
  );
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF5F4),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Color(0xFF087B75)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF087B75),
          ),
        ),
      ],
    ),
  );
}

class _SmallStatus extends StatelessWidget {
  const _SmallStatus({required this.label, required this.positive});
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: positive ? const Color(0xFFDCFCE7) : const Color(0xFFFFE4E8),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: positive ? const Color(0xFF067647) : const Color(0xFFB42318),
      ),
    ),
  );
}

class _CatalogPagination extends StatelessWidget {
  const _CatalogPagination({
    required this.page,
    required this.totalPages,
    required this.onPage,
  });
  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton.outlined(
        onPressed: page > 1 ? () => onPage(page - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Página $page de $totalPages',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      IconButton.outlined(
        onPressed: page < totalPages ? () => onPage(page + 1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _ModifierGroupsCard extends StatelessWidget {
  const _ModifierGroupsCard({
    required this.groups,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });
  final List<PedeOnModifierGroup> groups;
  final VoidCallback onCreate;
  final ValueChanged<PedeOnModifierGroup> onEdit;
  final ValueChanged<PedeOnModifierGroup> onDelete;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Perguntas, adicionais e bebidas',
    subtitle:
        'Crie grupos reutilizáveis e depois marque em quais produtos eles aparecem.',
    icon: Icons.tune_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo grupo'),
          ),
        ),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Exemplos: “Qual o ponto da carne?”, “Adicionais” e “Quer adicionar uma bebida?”.',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final group in groups)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 250,
                      maxWidth: 360,
                    ),
                    child: Card.outlined(
                      child: ListTile(
                        title: Text(group.name),
                        subtitle: Text(
                          '${group.options.length} opções • ${group.minimumSelections > 0 ? 'obrigatório' : 'opcional'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              value == 'edit' ? onEdit(group) : onDelete(group),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Excluir'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();
  @override
  Widget build(BuildContext context) => const _SectionCard(
    title: 'Nenhum produto encontrado',
    subtitle: 'Cadastre produtos no estoque ou altere os termos da busca.',
    icon: Icons.search_off_outlined,
    child: SizedBox.shrink(),
  );
}

String _stationTypeLabel(String value) => switch (value) {
  'picking' => 'Separação',
  'expedition' => 'Expedição',
  _ => 'Preparação',
};

class _StationEditorDialog extends StatefulWidget {
  const _StationEditorDialog({this.station});

  final PedeOnFulfillmentStation? station;

  @override
  State<_StationEditorDialog> createState() => _StationEditorDialogState();
}

class _StationEditorDialogState extends State<_StationEditorDialog> {
  late final name = TextEditingController(text: widget.station?.name ?? '');
  late final code = TextEditingController(text: widget.station?.code ?? '');
  late String stationType = widget.station?.stationType ?? 'preparation';
  late bool active = widget.station?.active ?? true;

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.station == null ? 'Nova estação' : 'Editar estação'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome',
              hintText: 'Ex.: Cozinha, Bar ou Confeitaria',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: code,
            enabled: widget.station == null,
            decoration: const InputDecoration(
              labelText: 'Código interno',
              hintText: 'Ex.: cozinha, bar, confeitaria',
              helperText: 'Use letras, números e hífen. Não muda após criar.',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: stationType,
            decoration: const InputDecoration(labelText: 'Tipo de operação'),
            items: const [
              DropdownMenuItem(value: 'preparation', child: Text('Preparação')),
              DropdownMenuItem(value: 'picking', child: Text('Separação')),
              DropdownMenuItem(value: 'expedition', child: Text('Expedição')),
            ],
            onChanged: (value) =>
                setState(() => stationType = value ?? 'preparation'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Estação ativa'),
            value: active,
            onChanged: (value) => setState(() => active = value),
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
          final stationName = name.text.trim();
          final stationCode = code.text
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), '');
          if (stationName.length < 2 || stationCode.length < 2) return;
          Navigator.pop(
            context,
            PedeOnFulfillmentStation(
              id: widget.station?.id,
              code: stationCode,
              name: stationName,
              stationType: stationType,
              sortOrder: widget.station?.sortOrder ?? 0,
              active: active,
            ),
          );
        },
        icon: const Icon(Icons.save_outlined),
        label: const Text('Salvar estação'),
      ),
    ],
  );
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.product,
    required this.categories,
    required this.modifierGroups,
    required this.stations,
  });
  final PedeOnCatalogProduct product;
  final List<PedeOnCategory> categories;
  final List<PedeOnModifierGroup> modifierGroups;
  final List<PedeOnFulfillmentStation> stations;
  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final name = TextEditingController(text: widget.product.displayName);
  late final description = TextEditingController(
    text: widget.product.description.isEmpty
        ? widget.product.productDescription
        : widget.product.description,
  );
  late final price = TextEditingController(
    text: widget.product.onlinePrice?.toStringAsFixed(2) ?? '',
  );
  late int? categoryId = widget.product.categoryId;
  late bool published = widget.product.published;
  late bool available = widget.product.available;
  late bool useOffer = widget.product.useProductOffer;
  late String fulfillmentMode = widget.product.fulfillmentMode;
  late String printPolicy = widget.product.printPolicy;
  late final enabledChannels = widget.product.enabledChannels.toSet();
  late String? productionStationCode =
      widget.product.productionStationCode.trim().isEmpty
      ? null
      : widget.product.productionStationCode;
  late final selectedGroupIds = widget.product.modifierGroupIds.toSet();

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu, color: Color(0xFF087B75)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configurar produto no cardápio',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        widget.product.productName,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: 'Nome no cardápio',
                      hintText: widget.product.productName,
                      helperText: 'Vazio mantém o nome original do estoque.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Descrição para o cliente',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int?>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sem categoria'),
                      ),
                      ...widget.categories.map(
                        (category) => DropdownMenuItem<int?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => categoryId = value),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Preço exclusivo online (opcional)',
                      prefixText: 'R\$ ',
                      helperText:
                          'Preço atual do estoque: ${_money(widget.product.salePrice)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SwitchLine(
                    title: 'Usar oferta do produto',
                    subtitle:
                        'Quando houver promoção ativa no estoque, aplica no cardápio.',
                    value: useOffer,
                    onChanged: (value) => setState(() => useOffer = value),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: fulfillmentMode,
                    decoration: const InputDecoration(
                      labelText: 'Como este produto será preparado?',
                      helperText:
                          'Define se o pedido vai para preparo, separação ou não terá tarefa operacional.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'inherit',
                        child: Text('Padrão da loja'),
                      ),
                      DropdownMenuItem(
                        value: 'preparation',
                        child: Text('Preparar (cozinha/produção)'),
                      ),
                      DropdownMenuItem(
                        value: 'picking',
                        child: Text('Separar no estoque'),
                      ),
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('Sem tarefa operacional'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => fulfillmentMode = value ?? 'inherit'),
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Onde este produto pode ser vendido',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'O PDV local sempre usa os produtos ativos do estoque. Aqui você controla somente os canais do PedeOn.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  for (final channel in const [
                    (
                      'pedeon_online',
                      'PedeOn Online',
                      'Site público e pedidos para entrega ou retirada',
                    ),
                    (
                      'onsite_qr',
                      'QR da mesa',
                      'Autoatendimento feito pelo cliente no salão',
                    ),
                  ])
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: enabledChannels.contains(channel.$1),
                      title: Text(channel.$2),
                      subtitle: Text(channel.$3),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          enabledChannels.add(channel.$1);
                        } else {
                          enabledChannels.remove(channel.$1);
                        }
                        if (channel.$1 == 'pedeon_online') {
                          published = value == true;
                        }
                      }),
                    ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: productionStationCode,
                    decoration: const InputDecoration(
                      labelText: 'Setor de produção (opcional)',
                      helperText:
                          'Ex.: Cozinha, Bar ou Expedição. A impressora é vinculada ao setor nas configurações de impressoras.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Padrão automático'),
                      ),
                      ...widget.stations
                          .where(
                            (station) =>
                                station.active ||
                                station.code == productionStationCode,
                          )
                          .map(
                            (station) => DropdownMenuItem<String?>(
                              value: station.code,
                              child: Text(station.name),
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setState(() => productionStationCode = value),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: printPolicy,
                    decoration: const InputDecoration(
                      labelText: 'Impressão do pedido',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'inherit',
                        child: Text('Padrão da loja'),
                      ),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text('Nunca imprimir'),
                      ),
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text('Somente manual'),
                      ),
                      DropdownMenuItem(
                        value: 'automatic',
                        child: Text('Imprimir automaticamente'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => printPolicy = value ?? 'inherit'),
                  ),
                  if (widget.modifierGroups.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Personalizações deste produto',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Marque somente o que deve aparecer neste item. Ex.: bebidas nos lanches e nada no pudim.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final group in widget.modifierGroups)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value:
                            group.id != null &&
                            selectedGroupIds.contains(group.id),
                        title: Text(group.name),
                        subtitle: Text(
                          group.minimumSelections > 0
                              ? 'Obrigatório • ${group.options.length} opções'
                              : 'Opcional • ${group.options.length} opções',
                        ),
                        onChanged: group.id == null
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  selectedGroupIds.add(group.id!);
                                } else {
                                  selectedGroupIds.remove(group.id);
                                }
                              }),
                      ),
                  ],
                  _SwitchLine(
                    title: 'Disponível para pedidos',
                    subtitle: 'Pause temporariamente sem remover a publicação.',
                    value: available,
                    onChanged: (value) => setState(() => available = value),
                  ),
                  _SwitchLine(
                    title: 'Publicado',
                    subtitle: 'Mostra este produto no cardápio público.',
                    value: published,
                    onChanged: (value) => setState(() => published = value),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () {
                    final rawPrice = price.text.trim().replaceAll(',', '.');
                    Navigator.pop(
                      context,
                      widget.product.copyWith(
                        categoryId: categoryId,
                        clearCategory: categoryId == null,
                        displayName: name.text,
                        description: description.text,
                        imageUrl: '',
                        onlinePrice: rawPrice.isEmpty
                            ? null
                            : double.tryParse(rawPrice),
                        clearOnlinePrice: rawPrice.isEmpty,
                        published: published,
                        available: available,
                        useProductOffer: useOffer,
                        fulfillmentMode: fulfillmentMode,
                        printPolicy: printPolicy,
                        enabledChannels: enabledChannels.toList(),
                        productionStationCode: productionStationCode ?? '',
                        modifierGroupIds: selectedGroupIds.toList(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar produto'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.badge,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final String? badge;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDCE6EF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A102A43),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE5F8F4),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: const Color(0xFF087B75)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            if (badge != null) Chip(label: Text(badge!)),
          ],
        ),
        const SizedBox(height: 22),
        child,
      ],
    ),
  );
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
            ),
          ],
        ),
      ),
      Switch(value: value, onChanged: onChanged),
    ],
  );
}

class _TerminalCard extends StatefulWidget {
  const _TerminalCard({
    required this.terminal,
    required this.saving,
    required this.onSave,
  });
  final PedeOnTerminalSettings terminal;
  final bool saving;
  final Future<bool> Function(PedeOnTerminalSettings) onSave;
  @override
  State<_TerminalCard> createState() => _TerminalCardState();
}

class _TerminalCardState extends State<_TerminalCard> {
  late PedeOnTerminalSettings draft = widget.terminal;
  static const labels = {
    'notify': 'Avisar',
    'accept': 'Aceitar',
    'prepare': 'Preparar',
    'dispatch': 'Despachar',
    'cancel': 'Cancelar',
    'print': 'Imprimir',
    'checkout': 'Receber / Caixa',
  };
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'PDV ${draft.cashRegisterNumber}',
    subtitle: '${draft.deviceLabel}  •  versão ${draft.appVersion}',
    icon: Icons.point_of_sale_outlined,
    badge: draft.terminalActive ? 'Ativo' : 'Inativo',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SwitchLine(
          title: 'Usar neste PDV',
          subtitle: 'Exibe a fila e as funções selecionadas.',
          value: draft.enabled,
          onChanged: (value) =>
              setState(() => draft = draft.copyWith(enabled: value)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in labels.entries)
              FilterChip(
                label: Text(entry.value),
                selected: draft.capabilities.contains(entry.key),
                onSelected: draft.enabled
                    ? (value) {
                        final next = [...draft.capabilities];
                        value ? next.add(entry.key) : next.remove(entry.key);
                        setState(
                          () => draft = draft.copyWith(
                            capabilities: next.toSet().toList(),
                          ),
                        );
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: widget.saving ? null : () => widget.onSave(draft),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar PDV'),
          ),
        ),
      ],
    ),
  );
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.title, required this.description});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFE9F7FF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFB9E2F5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.hub_outlined, color: Color(0xFF087CA7)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF475467)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.color,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color.withValues(alpha: .09),
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _EmptyTerminals extends StatelessWidget {
  const _EmptyTerminals();
  @override
  Widget build(BuildContext context) => const _SectionCard(
    title: 'Nenhum PDV disponível',
    subtitle:
        'Cadastre e ative um terminal PDV Windows antes de escolher quem recebe pedidos.',
    icon: Icons.devices_other_outlined,
    child: SizedBox.shrink(),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        Text(message ?? 'Não foi possível carregar o PedeOn.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar novamente'),
        ),
      ],
    ),
  );
}

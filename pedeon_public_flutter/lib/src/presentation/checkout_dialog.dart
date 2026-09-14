import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/cep_lookup_service.dart';
import '../domain/catalog_models.dart';
import 'customer_access_dialog.dart';
import 'storefront_view_model.dart';

Future<void> showCheckoutDialog(
  BuildContext context, {
  required StorefrontViewModel viewModel,
  required CartQuote quote,
}) async {
  if (!viewModel.store!.acceptingOrders) return;
  if (viewModel.customer == null) {
    final authenticated = await showCustomerAccessDialog(
      context,
      viewModel: viewModel,
    );
    if (!context.mounted || authenticated != true) return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CheckoutDialog(viewModel: viewModel, quote: quote),
  );
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.viewModel, required this.quote});
  final StorefrontViewModel viewModel;
  final CartQuote quote;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _document = TextEditingController();
  final _postalCode = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _complement = TextEditingController();
  final _neighborhood = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _cashChangeFor = TextEditingController();
  String? _fulfillment;
  String? _paymentMethod;
  String? _localPaymentMethod;
  bool _sending = false;
  bool _lookingUpCep = false;
  String? _error;
  String? _cepLookupError;
  String? _lastLookedUpCep;
  PublicOrder? _order;
  late CartQuote _quote;
  bool _deliveryQuoteReady = false;
  bool _calculatingDelivery = false;
  String? _deliveryQuoteError;
  Timer? _deliveryQuoteTimer;
  int _deliveryQuoteRevision = 0;

  Storefront get _store => widget.viewModel.store!;
  bool _paymentAvailableForFulfillment(PaymentOption option) {
    if (option.fulfillmentTypes.isNotEmpty) {
      return option.fulfillmentTypes.contains(_fulfillment);
    }

    // Catálogos publicados antes das modalidades por pagamento não trazem
    // `fulfillment_types`. Mantemos a compatibilidade, sem oferecer cartão
    // levado pelo entregador em pedidos de retirada.
    const deliveryOnlyMethods = {
      'credit_card_on_delivery',
      'debit_card_on_delivery',
    };
    return !deliveryOnlyMethods.contains(option.method) ||
        _fulfillment == 'delivery';
  }

  List<PaymentOption> get _visiblePaymentMethods => _store.paymentMethods
      .where(_paymentAvailableForFulfillment)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _quote = widget.quote;
    final customer = widget.viewModel.customer;
    if (customer != null) {
      _name.text = customer.name;
      _email.text = customer.email;
      if (customer.phone != null) _phone.text = customer.phone!;
    }
    final profile = widget.viewModel.customerProfile;
    _document.text = profile?.document ?? '';
    final savedAddress = profile?.deliveryAddress;
    if (savedAddress != null) {
      _postalCode.text = savedAddress.postalCode;
      _street.text = savedAddress.street;
      _number.text = savedAddress.number;
      _complement.text = savedAddress.complement ?? '';
      _neighborhood.text = savedAddress.neighborhood;
      _city.text = savedAddress.city;
      _state.text = savedAddress.state;
      _reference.text = savedAddress.reference ?? '';
    }
    for (final controller in [
      _postalCode,
      _street,
      _number,
      _complement,
      _neighborhood,
      _city,
      _state,
      _reference,
    ]) {
      controller.addListener(_onDeliveryAddressChanged);
    }
  }

  bool get _requiresLocalPaymentSelection => _paymentMethod == 'pay_at_pickup';

  bool get _canSubmit =>
      _store.acceptingOrders && _fulfillment != null && _paymentMethod != null;

  @override
  void dispose() {
    _deliveryQuoteTimer?.cancel();
    for (final controller in [
      _name,
      _phone,
      _email,
      _document,
      _postalCode,
      _street,
      _number,
      _complement,
      _neighborhood,
      _city,
      _state,
      _reference,
      _notes,
      _cashChangeFor,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final summary = _OrderSummary(
      viewModel: widget.viewModel,
      quote: _quote,
      sending: _sending,
      canSubmit: _canSubmit,
      onSubmit: _submit,
      embedded: compact,
      submitLabel: _fulfillment == 'delivery' && _calculatingDelivery
          ? 'Calculando entrega...'
          : _fulfillment == 'delivery' && !_deliveryQuoteReady
          ? 'Calcular entrega'
          : 'Fazer pedido • ${_currency(_quote.total)}',
    );
    return Dialog.fullscreen(
      child: SafeArea(
        child: _order == null
            ? _CheckoutForm(
                compact: compact,
                title: _Header(
                  onClose: _sending ? null : () => Navigator.pop(context),
                ),
                form: _buildForm(
                  compact,
                  trailing: compact
                      ? KeyedSubtree(
                          key: const Key('checkout-mobile-summary'),
                          child: summary,
                        )
                      : null,
                ),
                summary: summary,
              )
            : _OrderConfirmation(
                viewModel: widget.viewModel,
                order: _order!,
                onClose: () => Navigator.pop(context),
              ),
      ),
    );
  }

  Widget _buildForm(bool compact, {Widget? trailing}) => Form(
    key: _formKey,
    child: ListView(
      key: const Key('checkout-scroll'),
      padding: EdgeInsets.all(compact ? 18 : 30),
      children: [
        const _SectionTitle(
          icon: Icons.person_outline_rounded,
          title: 'Seus dados',
          subtitle: 'Usaremos estes dados somente para cuidar deste pedido.',
        ),
        const SizedBox(height: 16),
        _ResponsiveFields(
          children: [
            TextFormField(
              key: const Key('checkout-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (value) => _required(value, 'Informe seu nome.'),
            ),
            TextFormField(
              key: const Key('checkout-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _BrazilianPhoneFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Celular/WhatsApp *',
              ),
              validator: (value) =>
                  (value ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                  ? 'Informe um telefone válido.'
                  : null,
            ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail (opcional)'),
            ),
            TextFormField(
              controller: _document,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CPF/CNPJ (opcional)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const _SectionTitle(
          icon: Icons.shopping_bag_outlined,
          title: 'Como deseja receber?',
          subtitle: 'Escolha uma das opções disponibilizadas pela loja.',
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          key: const Key('checkout-fulfillment'),
          segments: [
            if (_store.fulfillmentOptions.contains('pickup'))
              const ButtonSegment(
                value: 'pickup',
                icon: Icon(Icons.storefront_outlined),
                label: Text('Retirar'),
              ),
            if (_store.fulfillmentOptions.contains('delivery'))
              const ButtonSegment(
                value: 'delivery',
                icon: Icon(Icons.delivery_dining_outlined),
                label: Text('Entrega'),
              ),
          ],
          emptySelectionAllowed: true,
          selected: {?_fulfillment},
          onSelectionChanged: (values) async {
            final value = values.firstOrNull;
            if (value == 'pickup') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Confirmar retirada'),
                  content: const Text(
                    'Você confirma que vai retirar o pedido no estabelecimento?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Voltar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirmar retirada'),
                    ),
                  ],
                ),
              );
              if (!mounted || confirmed != true) return;
            }
            if (value == null) return;
            setState(() {
              _fulfillment = value;
              _deliveryQuoteReady = false;
              _deliveryQuoteError = null;
              _quote = widget.quote;
              _paymentMethod = null;
              _localPaymentMethod = null;
            });
            _onDeliveryAddressChanged();
          },
        ),
        if (_fulfillment == 'delivery') ...[
          const SizedBox(height: 20),
          _ResponsiveFields(
            children: [
              TextFormField(
                key: const Key('checkout-postal-code'),
                controller: _postalCode,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.postalCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CepFormatter(),
                ],
                onChanged: _clearCepLookupState,
                onFieldSubmitted: (_) => _lookupCep(),
                decoration: InputDecoration(
                  labelText: 'CEP *',
                  hintText: '00000-000',
                  suffixIcon: _lookingUpCep
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Consultar CEP',
                          onPressed: _lookupCep,
                          icon: const Icon(Icons.search_rounded),
                        ),
                ),
                validator: (value) =>
                    (value ?? '').replaceAll(RegExp(r'\D'), '').length != 8
                    ? 'Informe um CEP válido.'
                    : null,
              ),
              if (_cepLookupError != null)
                _InlineFieldMessage(message: _cepLookupError!),
              TextFormField(
                key: const Key('checkout-street'),
                controller: _street,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Rua *'),
                validator: (value) => _required(value, 'Informe a rua.'),
              ),
              TextFormField(
                key: const Key('checkout-number'),
                controller: _number,
                decoration: const InputDecoration(labelText: 'Número *'),
                validator: (value) => _nonEmpty(value, 'Informe o número.'),
              ),
              TextFormField(
                controller: _complement,
                decoration: const InputDecoration(labelText: 'Complemento'),
              ),
              TextFormField(
                key: const Key('checkout-neighborhood'),
                controller: _neighborhood,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Bairro *'),
                validator: (value) => _required(value, 'Informe o bairro.'),
              ),
              TextFormField(
                key: const Key('checkout-city'),
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cidade *'),
                validator: (value) => _required(value, 'Informe a cidade.'),
              ),
              TextFormField(
                key: const Key('checkout-state'),
                controller: _state,
                textCapitalization: TextCapitalization.characters,
                maxLength: 2,
                decoration: const InputDecoration(
                  labelText: 'UF *',
                  counterText: '',
                ),
                validator: (value) =>
                    (value ?? '').trim().length != 2 ? 'Informe a UF.' : null,
              ),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Referência'),
              ),
            ],
          ),
          if (_deliveryQuoteError != null) ...[
            const SizedBox(height: 12),
            _WarningCard(message: _deliveryQuoteError!),
          ],
        ],
        const SizedBox(height: 30),
        _SectionTitle(
          icon: Icons.payments_outlined,
          title: 'Pagamento',
          subtitle: switch (_fulfillment) {
            'pickup' => 'Escolha como vai pagar na retirada.',
            'delivery' => 'Escolha como vai pagar na entrega.',
            _ => 'Escolha uma forma de pagamento.',
          },
        ),
        const SizedBox(height: 14),
        if (_visiblePaymentMethods.isEmpty)
          const SizedBox.shrink()
        else
          _PaymentChoices(
            fulfillment: _fulfillment,
            options: _visiblePaymentMethods,
            selectedMethod: _paymentMethod,
            selectedLocalMethod: _localPaymentMethod,
            onMethodChanged: (value) => setState(() {
              _paymentMethod = value;
              _localPaymentMethod = null;
              _cashChangeFor.clear();
            }),
            onLocalMethodChanged: (value) => setState(() {
              _localPaymentMethod = value;
              if (value != 'cash') _cashChangeFor.clear();
            }),
          ),
        if (_localPaymentMethod == 'cash') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _cashChangeFor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Troco para quanto? (opcional)',
              hintText: 'Ex.: 50,00',
            ),
            validator: (value) {
              if (_localPaymentMethod != 'cash' ||
                  (value ?? '').trim().isEmpty) {
                return null;
              }
              final amount = double.tryParse(value!.replaceAll(',', '.'));
              return amount == null || amount <= 0
                  ? 'Informe um valor válido para o troco.'
                  : null;
            },
          ),
        ],
        const SizedBox(height: 24),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observações do pedido',
            hintText: 'Ex.: retirar cebola, tocar o interfone...',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 18),
          _WarningCard(message: _error!),
        ],
        if (trailing != null) ...[const SizedBox(height: 28), trailing],
      ],
    ),
  );

  Future<void> _submit() async {
    if (_sending ||
        _calculatingDelivery ||
        !_canSubmit ||
        !_formKey.currentState!.validate()) {
      return;
    }
    if (_requiresLocalPaymentSelection && _localPaymentMethod == null) {
      setState(() => _error = 'Selecione como deseja pagar no local.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final deliveryAddress = _fulfillment == 'delivery'
          ? _currentDeliveryAddress()
          : null;
      final confirmedQuote = await widget.viewModel.confirmQuote(
        fulfillmentType: _fulfillment!,
        deliveryAddress: deliveryAddress,
      );
      if (!confirmedQuote.minimumOrderReached) {
        throw _CheckoutMessage(
          'O pedido mínimo é ${_currency(confirmedQuote.minimumOrderAmount)}.',
        );
      }
      if (_fulfillment == 'delivery' && !_deliveryQuoteReady) {
        if (mounted) {
          setState(() {
            _quote = confirmedQuote;
            _deliveryQuoteReady = true;
          });
        }
        return;
      }
      if (mounted) setState(() => _quote = confirmedQuote);
      final order = await widget.viewModel.placeOrder(
        CheckoutInput(
          idempotencyKey: widget.viewModel.checkoutIdempotencyKey(),
          customerName: _name.text.trim(),
          customerPhone: _phone.text.trim(),
          customerEmail: _nullable(_email.text),
          customerDocument: _nullable(_document.text),
          fulfillmentType: _fulfillment!,
          paymentMethod: _paymentMethod!,
          localPaymentMethod: _localPaymentMethod,
          cashChangeFor: _cashChangeFor.text.trim().isEmpty
              ? null
              : _cashChangeFor.text.trim().replaceAll(',', '.'),
          deliveryAddress: deliveryAddress,
          customerNotes: _nullable(_notes.text),
        ),
      );
      if (mounted) setState(() => _order = order);
      await _offerSaveCustomerProfile(deliveryAddress);
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _offerSaveCustomerProfile(
    DeliveryAddress? deliveryAddress,
  ) async {
    final document = _nullable(_document.text);
    final saved = widget.viewModel.customerProfile;
    final documentChanged = document != saved?.document;
    final addressChanged = !_sameAddress(
      deliveryAddress,
      saved?.deliveryAddress,
    );
    if (!documentChanged && !addressChanged) return;

    // O cliente já confirmou o pedido. CPF/CNPJ e endereço fazem parte do
    // cadastro do cliente; a forma de pagamento nunca é persistida.
    await widget.viewModel.saveCustomerProfile(
      document: document,
      deliveryAddress: deliveryAddress,
    );
  }

  bool _sameAddress(DeliveryAddress? first, DeliveryAddress? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;
    return first.postalCode == second.postalCode &&
        first.street == second.street &&
        first.number == second.number &&
        first.complement == second.complement &&
        first.neighborhood == second.neighborhood &&
        first.city == second.city &&
        first.state == second.state &&
        first.reference == second.reference;
  }

  DeliveryAddress _currentDeliveryAddress() => DeliveryAddress(
    postalCode: _postalCode.text.trim(),
    street: _street.text.trim(),
    number: _number.text.trim(),
    complement: _nullable(_complement.text),
    neighborhood: _neighborhood.text.trim(),
    city: _city.text.trim(),
    state: _state.text.trim().toUpperCase(),
    reference: _nullable(_reference.text),
  );

  bool get _hasCompleteDeliveryAddress =>
      _postalCode.text.replaceAll(RegExp(r'\D'), '').length == 8 &&
      _street.text.trim().isNotEmpty &&
      _number.text.trim().isNotEmpty &&
      _neighborhood.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      _state.text.trim().length == 2;

  void _onDeliveryAddressChanged() {
    _deliveryQuoteTimer?.cancel();
    final revision = ++_deliveryQuoteRevision;
    if (!mounted || _fulfillment != 'delivery') return;

    if (_deliveryQuoteReady || _deliveryQuoteError != null) {
      setState(() {
        _deliveryQuoteReady = false;
        _deliveryQuoteError = null;
        _quote = widget.quote;
      });
    }
    if (!_hasCompleteDeliveryAddress || _lookingUpCep) return;

    _deliveryQuoteTimer = Timer(
      const Duration(milliseconds: 450),
      () => _refreshDeliveryQuote(revision),
    );
  }

  Future<void> _refreshDeliveryQuote(int revision) async {
    if (!mounted ||
        revision != _deliveryQuoteRevision ||
        _fulfillment != 'delivery' ||
        !_hasCompleteDeliveryAddress) {
      return;
    }
    setState(() {
      _calculatingDelivery = true;
      _deliveryQuoteError = null;
    });
    try {
      final quote = await widget.viewModel.confirmQuote(
        fulfillmentType: 'delivery',
        deliveryAddress: _currentDeliveryAddress(),
      );
      if (!mounted || revision != _deliveryQuoteRevision) return;
      setState(() {
        _quote = quote;
        _deliveryQuoteReady = true;
      });
    } catch (_) {
      if (!mounted || revision != _deliveryQuoteRevision) return;
      setState(() {
        _deliveryQuoteReady = false;
        _deliveryQuoteError =
            'Não foi possível calcular a entrega para este endereço. Confira os dados ou tente novamente.';
      });
    } finally {
      if (mounted && revision == _deliveryQuoteRevision) {
        setState(() => _calculatingDelivery = false);
      }
    }
  }

  void _clearCepLookupState(String value) {
    final cep = value.replaceAll(RegExp(r'\D'), '');
    if (cep == _lastLookedUpCep && _cepLookupError == null) return;
    setState(() {
      _lastLookedUpCep = null;
      _cepLookupError = null;
    });
  }

  Future<void> _lookupCep() async {
    final cep = _postalCode.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8 || _lookingUpCep) return;
    setState(() {
      _lookingUpCep = true;
      _cepLookupError = null;
    });
    try {
      final address = await const CepLookupService().lookup(cep);
      if (!mounted) return;
      setState(() {
        _lastLookedUpCep = cep;
        if (address.street.isNotEmpty) _street.text = address.street;
        if (address.neighborhood.isNotEmpty) {
          _neighborhood.text = address.neighborhood;
        }
        if (address.city.isNotEmpty) _city.text = address.city;
        if (address.state.isNotEmpty) _state.text = address.state;
      });
    } on CepNotFoundException {
      if (mounted) {
        setState(
          () => _cepLookupError = 'CEP não encontrado. Confira os dígitos.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _cepLookupError =
              'Não foi possível consultar o CEP agora. Preencha o endereço manualmente.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _lookingUpCep = false);
        _onDeliveryAddressChanged();
      }
    }
  }
}

class _InlineFieldMessage extends StatelessWidget {
  const _InlineFieldMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = raw.substring(0, raw.length.clamp(0, 8));
    final text = digits.length > 5
        ? '${digits.substring(0, 5)}-${digits.substring(5)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _BrazilianPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = raw.substring(0, raw.length.clamp(0, 11));
    final text = switch (digits.length) {
      0 => '',
      <= 2 => '($digits',
      <= 6 => '(${digits.substring(0, 2)}) ${digits.substring(2)}',
      <= 10 =>
        '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}',
      _ =>
        '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}',
    };
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CheckoutForm extends StatelessWidget {
  const _CheckoutForm({
    required this.compact,
    required this.title,
    required this.form,
    required this.summary,
  });
  final bool compact;
  final Widget title;
  final Widget form;
  final Widget summary;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      title,
      Expanded(
        child: compact
            ? form
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: form),
                  SizedBox(width: 390, child: summary),
                ],
              ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finalizar pedido',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text(
                'Confira seus dados antes de enviar.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        const Text(
          'PedeOn by Lyncar',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.viewModel,
    required this.quote,
    required this.sending,
    required this.canSubmit,
    required this.onSubmit,
    required this.embedded,
    required this.submitLabel,
  });
  final StorefrontViewModel viewModel;
  final CartQuote quote;
  final bool sending;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final bool embedded;
  final String submitLabel;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF7FAFC),
    padding: const EdgeInsets.all(22),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resumo',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (embedded)
            ...viewModel.cart.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${line.quantity}× ${line.product.name}'),
                    ),
                    Text(_currency(line.total)),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Scrollbar(
                child: ListView(
                  shrinkWrap: true,
                  primary: false,
                  children: viewModel.cart
                      .map(
                        (line) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      key: Key(
                                        'checkout-summary-product-${line.product.id}',
                                      ),
                                      '${line.quantity}× ${line.product.name}',
                                    ),
                                    for (final label in line.modifierLabels)
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(_currency(line.total)),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          const Divider(height: 24),
          if (quote.deliveryFee > 0 || quote.deliveryZoneName != null) ...[
            if (quote.deliveryZoneName != null)
              _SummaryValue(label: 'Área', value: quote.deliveryZoneName!),
            _SummaryValue(label: 'Subtotal', value: _currency(quote.subtotal)),
            _SummaryValue(
              label: 'Entrega',
              value: quote.deliveryFee == 0
                  ? 'Grátis'
                  : _currency(quote.deliveryFee),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _currency(quote.total),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (quote.estimatedMinutesMin != null) ...[
            const SizedBox(height: 8),
            Text(
              'Previsão de entrega: ${quote.estimatedMinutesMin}'
              '${quote.estimatedMinutesMax == null ? '' : '–${quote.estimatedMinutesMax}'} min',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('submit-order'),
            onPressed: sending || !canSubmit ? null : onSubmit,
            icon: sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(sending ? 'Enviando...' : submitLabel),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seu pedido será enviado à loja e ainda não será convertido em venda.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    ),
  );
}

class _OrderConfirmation extends StatefulWidget {
  const _OrderConfirmation({
    required this.viewModel,
    required this.order,
    required this.onClose,
  });
  final StorefrontViewModel viewModel;
  final PublicOrder order;
  final VoidCallback onClose;

  @override
  State<_OrderConfirmation> createState() => _OrderConfirmationState();
}

class _OrderConfirmationState extends State<_OrderConfirmation> {
  late PublicOrder _order;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool get _finished =>
      const {'completed', 'cancelled'}.contains(_order.status);

  void _scheduleRefresh() {
    if (_finished) return;
    _refreshTimer = Timer(const Duration(seconds: 12), _refresh);
  }

  Future<void> _refresh() async {
    try {
      final updated = await widget.viewModel.trackOrder(_order.trackingToken);
      if (mounted) setState(() => _order = updated);
    } catch (_) {
      // Mantém a confirmação utilizável durante uma oscilação de rede.
    } finally {
      if (mounted) _scheduleRefresh();
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFFDDF7E8),
                  child: Icon(
                    Icons.check_rounded,
                    size: 40,
                    color: Color(0xFF087443),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pedido recebido!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  _order.displayNumber,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                _InfoRow(label: 'Situação', value: _statusLabel(_order.status)),
                _InfoRow(label: 'Total', value: _currency(_order.total)),
                _InfoRow(
                  label: 'Forma de pagamento',
                  value: _order.payment.displayName,
                ),
                if (_order.estimatedMinutesMin != null)
                  _InfoRow(
                    label: 'Previsão',
                    value:
                        '${_order.estimatedMinutesMin}'
                        '${_order.estimatedMinutesMax == null ? '' : '–${_order.estimatedMinutesMax}'} min',
                  ),
                if (_order.payment.method == 'manual_pix') ...[
                  const Divider(height: 30),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pague com Pix',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(_order.payment.pixKey ?? ''),
                  if ((_order.payment.recipientName ?? '').isNotEmpty)
                    Text('Recebedor: ${_order.payment.recipientName}'),
                  if ((_order.payment.instructions ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_order.payment.instructions!),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _order.payment.pixKey ?? ''),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chave Pix copiada.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar chave Pix'),
                  ),
                ],
                if ((_order.payment.checkoutUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(_order.payment.checkoutUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir pagamento Pix'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _order.payment.checkoutUrl!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link de pagamento copiado.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar link de pagamento'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Guarde o número do pedido. A loja ainda precisa confirmar o pagamento e aceitar o preparo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('Voltar ao cardápio'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'awaiting_payment' => 'Aguardando pagamento',
  'awaiting_acceptance' => 'Aguardando confirmação da loja',
  'accepted' => 'Pedido aceito',
  'in_preparation' => 'Em preparação',
  'ready' => 'Pronto',
  'out_for_delivery' => 'Saiu para entrega',
  'completed' => 'Concluído',
  'cancelled' => 'Cancelado',
  _ => 'Pedido recebido',
};

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 680;
      if (!twoColumns) {
        return Column(
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(height: 14),
            ],
          ],
        );
      }
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: children
            .map(
              (child) => SizedBox(
                width: (constraints.maxWidth - 14) / 2,
                child: child,
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _PaymentChoices extends StatelessWidget {
  const _PaymentChoices({
    required this.fulfillment,
    required this.options,
    required this.selectedMethod,
    required this.selectedLocalMethod,
    required this.onMethodChanged,
    required this.onLocalMethodChanged,
  });

  final String? fulfillment;
  final List<PaymentOption> options;
  final String? selectedMethod;
  final String? selectedLocalMethod;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onLocalMethodChanged;

  @override
  Widget build(BuildContext context) {
    final local = options
        .where((option) => option.method == 'pay_at_pickup')
        .firstOrNull;
    final localDeliveryMethods = local?.localMethods ?? const <String>[];
    final showLocalDeliveryOnly =
        fulfillment == 'delivery' && localDeliveryMethods.isNotEmpty;
    final regular = options
        .where(
          (option) =>
              option.method != 'pay_at_pickup' && !showLocalDeliveryOnly,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (regular.isNotEmpty)
          RadioGroup<String>(
            groupValue: selectedMethod,
            onChanged: onMethodChanged,
            child: Column(
              children: regular
                  .map(
                    (option) => RadioListTile<String>(
                      key: Key('payment-${option.method}'),
                      value: option.method,
                      title: Text(_paymentTitle(option, fulfillment)),
                      subtitle: Text(_paymentDescription(option, fulfillment)),
                      secondary: Icon(_paymentIcon(option.method)),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xFFD7E1E8)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        if (local != null && fulfillment != null) ...[
          if (regular.isNotEmpty) const SizedBox(height: 18),
          Text(
            fulfillment == 'delivery'
                ? 'Como vai pagar na entrega?'
                : 'Como vai pagar na retirada?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: selectedMethod == 'pay_at_pickup'
                ? selectedLocalMethod
                : null,
            onChanged: (value) {
              onMethodChanged('pay_at_pickup');
              onLocalMethodChanged(value);
            },
            child: Column(
              children: local.localMethods
                  .map(
                    (method) => RadioListTile<String>(
                      key: Key('local-payment-$method'),
                      value: method,
                      title: Text(_localMethodLabel(method)),
                      secondary: Icon(_localPaymentIcon(method)),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xFFD7E1E8)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(child: Icon(icon)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ],
  );
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

String? _required(String? value, String message) =>
    (value ?? '').trim().length < 2 ? message : null;
String? _nonEmpty(String? value, String message) =>
    (value ?? '').trim().isEmpty ? message : null;
String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();

class _CheckoutMessage implements Exception {
  const _CheckoutMessage(this.message);
  final String message;

  @override
  String toString() => message;
}

String _paymentDescription(
  PaymentOption option,
  String? fulfillment,
) => switch (option.method) {
  'manual_pix' => 'A loja confere o pagamento antes de aceitar.',
  'infinitepay_pix' => 'Pagamento seguro no checkout da InfinitePay.',
  'credit_card_on_delivery' => 'Pagamento com maquininha na entrega.',
  'debit_card_on_delivery' => 'Pagamento com maquininha na entrega.',
  'pay_at_pickup' =>
    option.localMethods.isEmpty
        ? fulfillment == 'delivery'
              ? 'Você paga na entrega.'
              : 'Você paga na retirada.'
        : fulfillment == 'delivery'
        ? 'Você paga na entrega: ${option.localMethods.map(_localMethodLabel).join(', ')}.'
        : 'Você paga na retirada: ${option.localMethods.map(_localMethodLabel).join(', ')}.',
  _ => 'Forma de pagamento disponibilizada pela loja.',
};

String _paymentTitle(PaymentOption option, String? fulfillment) =>
    fulfillment == 'delivery'
    ? switch (option.method) {
        'credit_card_on_delivery' => 'Crédito',
        'debit_card_on_delivery' => 'Débito',
        _ => option.displayName,
      }
    : option.displayName;

String _localMethodLabel(String method) => switch (method) {
  'cash' => 'dinheiro',
  'pix' => 'Pix',
  'credit_card' => 'crédito',
  'debit_card' => 'débito',
  _ => method,
};
IconData _localPaymentIcon(String method) => switch (method) {
  'cash' => Icons.payments_outlined,
  'pix' => Icons.pix_outlined,
  'credit_card' || 'debit_card' => Icons.credit_card_outlined,
  _ => Icons.payment_outlined,
};
IconData _paymentIcon(String method) => switch (method) {
  'manual_pix' => Icons.pix_rounded,
  'infinitepay_pix' => Icons.open_in_new_rounded,
  _ => Icons.credit_card_rounded,
};
String _currency(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

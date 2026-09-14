import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/cep_service.dart';
import '../domain/pedeon_settings.dart';

class DeliveryZoneEditorDialog extends StatefulWidget {
  const DeliveryZoneEditorDialog({super.key, this.zone});

  final PedeOnDeliveryZone? zone;

  @override
  State<DeliveryZoneEditorDialog> createState() =>
      _DeliveryZoneEditorDialogState();
}

class _DeliveryZoneEditorDialogState extends State<DeliveryZoneEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lookupCep;
  late final TextEditingController _postalCodePrefix;
  late final TextEditingController _neighborhood;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _fee;
  late final TextEditingController _minimum;
  late final TextEditingController _freeAbove;
  late final TextEditingController _estimateMin;
  late final TextEditingController _estimateMax;
  late final TextEditingController _radiusKm;
  late String _matchType;
  late bool _active;
  bool _lookingUpCep = false;
  CepAddress? _locatedAddress;
  LatLng? _mapCenter;

  @override
  void initState() {
    super.initState();
    final zone = widget.zone;
    _name = TextEditingController(text: zone?.name ?? '');
    _lookupCep = TextEditingController();
    _postalCodePrefix = TextEditingController(
      text: zone?.postalCodePrefix ?? '',
    );
    _neighborhood = TextEditingController(text: zone?.neighborhood ?? '');
    _city = TextEditingController(text: zone?.city ?? '');
    _state = TextEditingController(text: zone?.state ?? '');
    _fee = TextEditingController(text: _money(zone?.feeAmount));
    _minimum = TextEditingController(text: _money(zone?.minimumOrderAmount));
    _freeAbove = TextEditingController(
      text: zone?.freeDeliveryThreshold == null
          ? ''
          : _money(zone!.freeDeliveryThreshold),
    );
    _estimateMin = TextEditingController(
      text: zone?.estimatedMinutesMin?.toString() ?? '',
    );
    _estimateMax = TextEditingController(
      text: zone?.estimatedMinutesMax?.toString() ?? '',
    );
    _radiusKm = TextEditingController(
      text: zone?.radiusKm?.toStringAsFixed(1) ?? '3.0',
    );
    if (zone?.centerLatitude != null && zone?.centerLongitude != null) {
      _mapCenter = LatLng(zone!.centerLatitude!, zone.centerLongitude!);
    }
    _matchType = zone?.matchType ?? 'radius';
    _active = zone?.active ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _lookupCep,
      _postalCodePrefix,
      _neighborhood,
      _city,
      _state,
      _fee,
      _minimum,
      _freeAbove,
      _estimateMin,
      _estimateMax,
      _radiusKm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 900,
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 640;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Nome da área',
                            hintText: 'Centro, Zona Sul, CEP 17012...',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _matchType,
                          decoration: const InputDecoration(
                            labelText: 'Como deseja definir a cobertura?',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'radius',
                              child: Text('Raio no mapa (recomendado)'),
                            ),
                            DropdownMenuItem(
                              value: 'postal_code_prefix',
                              child: Text('Início do CEP'),
                            ),
                            DropdownMenuItem(
                              value: 'neighborhood',
                              child: Text('Bairro'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _matchType = value ?? _matchType),
                        ),
                        const SizedBox(height: 16),
                        _cepLookupPanel(wide),
                        const SizedBox(height: 20),
                        if (_matchType == 'postal_code_prefix')
                          TextFormField(
                            controller: _postalCodePrefix,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Início do CEP',
                              helperText:
                                  'Quanto mais dígitos, mais específica é a área. Ex.: 17012.',
                            ),
                            validator: (value) {
                              final digits = (value ?? '').replaceAll(
                                RegExp(r'\D'),
                                '',
                              );
                              return digits.length < 3
                                  ? 'Informe ao menos 3 dígitos.'
                                  : null;
                            },
                          )
                        else if (_matchType == 'neighborhood')
                          TextFormField(
                            controller: _neighborhood,
                            decoration: const InputDecoration(
                              labelText: 'Bairro',
                            ),
                            validator: _required,
                          )
                        else if (_matchType == 'radius')
                          const SizedBox.shrink(),
                        const SizedBox(height: 16),
                        _responsivePair(
                          wide,
                          TextFormField(
                            controller: _city,
                            decoration: const InputDecoration(
                              labelText: 'Cidade (opcional)',
                            ),
                          ),
                          TextFormField(
                            controller: _state,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 2,
                            decoration: const InputDecoration(
                              labelText: 'UF (opcional)',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _responsivePair(
                          wide,
                          _moneyField(_fee, 'Taxa de entrega'),
                          _moneyField(_minimum, 'Pedido mínimo nesta área'),
                        ),
                        const SizedBox(height: 16),
                        _moneyField(
                          _freeAbove,
                          'Entrega grátis a partir de (opcional)',
                          required: false,
                        ),
                        const SizedBox(height: 16),
                        _responsivePair(
                          wide,
                          _integerField(_estimateMin, 'Deslocamento mínimo'),
                          _integerField(_estimateMax, 'Deslocamento máximo'),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Área ativa'),
                          subtitle: const Text(
                            'Desative para pausar entregas sem perder a configuração.',
                          ),
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                        ),
                      ],
                    );
                  },
                ),
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
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar área'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 14, 18),
    child: Row(
      children: [
        const CircleAvatar(child: Icon(Icons.delivery_dining_outlined)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.zone == null ? 'Nova área de entrega' : 'Editar área',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Defina alcance, taxa, mínimo e tempo de deslocamento.',
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
  );

  Widget _responsivePair(bool wide, Widget first, Widget second) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        )
      : Column(children: [first, const SizedBox(height: 16), second]);

  Widget _cepLookupPanel(bool wide) {
    final address = _locatedAddress;
    final lookup = TextFormField(
      controller: _lookupCep,
      keyboardType: TextInputType.number,
      maxLength: 9,
      decoration: InputDecoration(
        labelText: _matchType == 'radius'
            ? 'CEP do ponto central'
            : 'Consultar um CEP da área',
        hintText: '00000-000',
        counterText: '',
        prefixIcon: Icon(Icons.location_searching_outlined),
        helperText: 'Localiza o endereço e preenche a cobertura abaixo.',
      ),
      onFieldSubmitted: (_) => _lookupAddress(),
    );
    final button = FilledButton.tonalIcon(
      onPressed: _lookingUpCep ? null : _lookupAddress,
      icon: _lookingUpCep
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Text('Buscar CEP'),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        border: Border.all(color: const Color(0xFFD7E0EA)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Localize antes de configurar',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Consulte um CEP real para evitar bairro, cidade ou faixa digitados incorretamente.',
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lookup),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: button,
                  ),
                ],
              )
            else ...[
              lookup,
              const SizedBox(height: 10),
              button,
            ],
            if (address != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.place_outlined)),
                title: Text(
                  [
                    address.street,
                    address.neighborhood,
                  ].where((item) => item.trim().isNotEmpty).join(' • '),
                ),
                subtitle: Text('${address.city} - ${address.state}'),
                trailing: _matchType == 'radius'
                    ? null
                    : TextButton.icon(
                        onPressed: _openLocatedAddress,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Ver no mapa'),
                      ),
              ),
            ],
            if (_matchType == 'radius') ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _radiusKm,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Raio de entrega',
                  suffixText: 'km',
                  helperText:
                      'Busque o CEP e o círculo mostrará a cobertura no mapa.',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final radius = _decimal(value);
                  if (radius == null || radius <= 0 || radius > 500) {
                    return 'Informe um raio entre 0,1 e 500 km.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _embeddedMap(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _embeddedMap() {
    final center = _mapCenter;
    if (center == null) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E0EA)),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 42),
            SizedBox(height: 10),
            Text(
              'Consulte acima o CEP do ponto central da entrega para desenhar o raio no mapa.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final radius = (_decimal(_radiusKm.text) ?? 0) * 1000;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 340,
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'br.com.lyncar.pedeon',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: center,
                  radius: radius,
                  useRadiusInMeter: true,
                  color: const Color(0x332196F3),
                  borderColor: const Color(0xFF087F79),
                  borderStrokeWidth: 3,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 46,
                  height: 46,
                  child: const Icon(
                    Icons.storefront,
                    size: 38,
                    color: Color(0xFF087F79),
                  ),
                ),
              ],
            ),
            RichAttributionWidget(
              attributions: const [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookupAddress() async {
    setState(() => _lookingUpCep = true);
    try {
      final address = await const CepService().lookup(_lookupCep.text);
      if (!mounted) return;
      final digits = _lookupCep.text.replaceAll(RegExp(r'\D'), '');
      setState(() {
        _locatedAddress = address;
        if (address.latitude != null && address.longitude != null) {
          _mapCenter = LatLng(address.latitude!, address.longitude!);
        }
        _city.text = address.city;
        _state.text = address.state;
        if (_matchType == 'neighborhood') {
          _neighborhood.text = address.neighborhood;
        } else if (_matchType == 'postal_code_prefix') {
          _postalCodePrefix.text = digits;
        }
      });
    } on CepLookupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível consultar o CEP.')),
      );
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }

  Future<void> _openLocatedAddress() async {
    final address = _locatedAddress;
    if (address == null) return;
    final query = [
      address.street,
      address.neighborhood,
      address.city,
      address.state,
      _lookupCep.text,
    ].where((item) => item.trim().isNotEmpty).join(', ');
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o mapa.')),
      );
    }
  }

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    bool required = true,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, prefixText: r'R$ '),
    validator: (value) {
      if (!required && (value ?? '').trim().isEmpty) return null;
      return _decimal(value) == null ? 'Informe um valor válido.' : null;
    },
  );

  Widget _integerField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) return null;
          final parsed = int.tryParse(value!.trim());
          return parsed == null || parsed <= 0 ? 'Minutos inválidos.' : null;
        },
      );

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Este campo é obrigatório.' : null;

  double? _decimal(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  String _money(double? value) => (value ?? 0).toStringAsFixed(2);

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_matchType == 'radius' && _mapCenter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Consulte o CEP do ponto central antes de salvar.'),
        ),
      );
      return;
    }
    final estimateMin = int.tryParse(_estimateMin.text.trim());
    final estimateMax = int.tryParse(_estimateMax.text.trim());
    if (estimateMin != null &&
        estimateMax != null &&
        estimateMin > estimateMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O prazo mínimo não pode superar o máximo.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      PedeOnDeliveryZone(
        id: widget.zone?.id,
        name: _name.text,
        matchType: _matchType,
        postalCodePrefix: _postalCodePrefix.text,
        neighborhood: _neighborhood.text,
        city: _city.text,
        state: _state.text,
        centerLatitude: _matchType == 'radius' ? _mapCenter?.latitude : null,
        centerLongitude: _matchType == 'radius' ? _mapCenter?.longitude : null,
        radiusKm: _matchType == 'radius' ? _decimal(_radiusKm.text) : null,
        feeAmount: _decimal(_fee.text) ?? 0,
        minimumOrderAmount: _decimal(_minimum.text) ?? 0,
        freeDeliveryThreshold: _freeAbove.text.trim().isEmpty
            ? null
            : _decimal(_freeAbove.text),
        estimatedMinutesMin: estimateMin,
        estimatedMinutesMax: estimateMax,
        sortOrder: widget.zone?.sortOrder ?? 0,
        active: _active,
      ),
    );
  }
}

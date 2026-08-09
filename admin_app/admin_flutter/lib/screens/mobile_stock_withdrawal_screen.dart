import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/mobile_scanner_assist_controls.dart';
import 'mobile_product_form_sheet.dart';

const _mobileWithdrawalReasons = {
  'loss_damage': 'Perda ou avaria',
  'expired': 'Produto vencido',
  'internal_consumption': 'Consumo interno',
  'employee_meal': 'Alimentação da equipe',
  'production_use': 'Uso na produção',
  'sample_gift': 'Amostra ou brinde',
  'theft': 'Furto ou desaparecimento',
  'inventory_adjustment': 'Ajuste de inventário',
  'other': 'Outros',
};

class MobileStockWithdrawalScreen extends StatefulWidget {
  const MobileStockWithdrawalScreen({super.key, required this.session});

  final Session session;

  @override
  State<MobileStockWithdrawalScreen> createState() =>
      _MobileStockWithdrawalScreenState();
}

class _MobileStockWithdrawalScreenState
    extends State<MobileStockWithdrawalScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );
  final _manualCode = TextEditingController();

  bool _scannerPaused = false;
  bool _smallCodeMode = false;
  double _scannerZoom = 0;
  bool _loading = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _manualCode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_scannerPaused || _loading) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .cast<String?>()
        .firstWhere((value) => value != null, orElse: () => null);
    if (code == null) return;
    _openCode(code);
  }

  Future<void> _openManualCode() async {
    final code = _manualCode.text.trim();
    if (code.isEmpty) return;
    _manualCode.clear();
    await _openCode(code);
  }

  Future<void> _openCode(String code) async {
    setState(() {
      _scannerPaused = true;
      _loading = true;
      _error = null;
      _message = null;
    });
    await _scannerController.stop();
    try {
      final product = await _api.lookupProductByCode(
        widget.session.token,
        code,
      );
      if (!mounted) return;
      if (product.productType == 'servico') {
        setState(() => _error = 'Serviços não possuem saldo de estoque.');
        return;
      }
      final movementNumber = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) =>
            _MobileWithdrawalSheet(product: product, onSave: _saveWithdrawal),
      );
      if (movementNumber != null && mounted) {
        setState(() {
          _message = 'Baixa $movementNumber registrada com sucesso.';
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      final created = await _askCreateProduct(code, error.message);
      if (created != null) {
        setState(() {
          _message = 'Produto ${created.name} cadastrado nesta empresa.';
          _error = null;
        });
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível ler o produto.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _scannerPaused = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) await _scannerController.start();
      }
    }
  }

  Future<String> _saveWithdrawal({
    required Product product,
    required double quantity,
    required String reasonCode,
    String? notes,
  }) async {
    final movement = await _api.createStockWithdrawal(
      widget.session.token,
      productId: product.id,
      quantity: quantity,
      reasonCode: reasonCode,
      notes: notes,
    );
    return movement.sourceNumber ?? 'B${movement.id}';
  }

  Future<Product?> _askCreateProduct(String code, String lookupMessage) async {
    final wantsCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Produto nao encontrado'),
        content: Text(
          '$lookupMessage\n\nDeseja cadastrar este produto agora neste cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Cadastrar'),
          ),
        ],
      ),
    );
    if (wantsCreate != true || !mounted) return null;
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MobileProductFormSheet(
        api: _api,
        token: widget.session.token,
        initialBarcode: code,
      ),
    );
  }

  Future<void> _openProductRegistration({String? code}) async {
    final created = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MobileProductFormSheet(
        api: _api,
        token: widget.session.token,
        initialBarcode: code,
      ),
    );
    if (created != null && mounted) {
      setState(() {
        _message = 'Produto ${created.name} cadastrado nesta empresa.';
        _error = null;
      });
    }
  }

  Future<void> _setScannerZoom(double value) async {
    final zoom = value.clamp(0.0, 1.0);
    setState(() {
      _scannerZoom = zoom;
      _smallCodeMode = zoom >= 0.45;
    });
    try {
      await _scannerController.setZoomScale(zoom);
    } catch (_) {
      // Alguns navegadores nao suportam zoom manual da camera.
    }
  }

  Future<void> _toggleSmallCodeMode() async {
    await _setScannerZoom(_smallCodeMode ? 0 : 0.62);
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Lanterna nao disponivel neste aparelho/navegador.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FB),
      appBar: AppBar(title: const Text('Baixa de estoque')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            const Text(
              'Leia o produto',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'O responsável será o usuário conectado no app.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              _MobileInfoBox(
                message: _error!,
                icon: Icons.error_outline,
                color: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 12),
            ],
            if (_message != null) ...[
              _MobileInfoBox(
                message: _message!,
                icon: Icons.check_circle_outline,
                color: const Color(0xFF059669),
              ),
              const SizedBox(height: 12),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleDetect,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF0A66D8),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                    if (_loading)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66000000),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: MobileScannerAssistControls(
                        zoom: _scannerZoom,
                        smallCodeMode: _smallCodeMode,
                        onZoomChanged: _setScannerZoom,
                        onSmallCodeToggle: _toggleSmallCodeMode,
                        onTorchToggle: _toggleTorch,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCode,
                    decoration: const InputDecoration(
                      labelText: 'Código manual',
                      prefixIcon: Icon(Icons.qr_code_2_outlined),
                    ),
                    onSubmitted: (_) => _openManualCode(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Buscar código',
                  onPressed: _loading ? null : _openManualCode,
                  icon: const Icon(Icons.keyboard_return),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _openProductRegistration(
                      code: _manualCode.text.trim().isEmpty
                          ? null
                          : _manualCode.text.trim(),
                    ),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Cadastrar produto'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileWithdrawalSheet extends StatefulWidget {
  const _MobileWithdrawalSheet({required this.product, required this.onSave});

  final Product product;
  final Future<String> Function({
    required Product product,
    required double quantity,
    required String reasonCode,
    String? notes,
  })
  onSave;

  @override
  State<_MobileWithdrawalSheet> createState() => _MobileWithdrawalSheetState();
}

class _MobileWithdrawalSheetState extends State<_MobileWithdrawalSheet> {
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  String _reasonCode = 'loss_damage';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = parseBrazilianNumber(_quantity.text);
    if (quantity <= 0) {
      setState(() => _error = 'Informe uma quantidade maior que zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final number = await widget.onSave(
        product: widget.product,
        quantity: quantity,
        reasonCode: _reasonCode,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(number);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível registrar a baixa.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Saldo atual: ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: const [BrazilianDecimalInputFormatter()],
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reasonCode,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                for (final entry in _mobileWithdrawalReasons.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _reasonCode = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MobileInfoBox(
                message: _error!,
                icon: Icons.error_outline,
                color: const Color(0xFFDC2626),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.remove_circle_outline),
              label: const Text('Dar baixa'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileInfoBox extends StatelessWidget {
  const _MobileInfoBox({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

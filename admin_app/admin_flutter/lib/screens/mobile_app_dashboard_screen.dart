import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import 'mobile_product_form_sheet.dart';
import 'mobile_receiving_screen.dart';
import 'mobile_stock_withdrawal_screen.dart';

class MobileAppDashboardScreen extends StatefulWidget {
  const MobileAppDashboardScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final Session session;
  final VoidCallback onLogout;

  @override
  State<MobileAppDashboardScreen> createState() =>
      _MobileAppDashboardScreenState();
}

class _MobileAppDashboardScreenState extends State<MobileAppDashboardScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  String? _message;

  bool get _canReceive =>
      widget.session.can('stock:entries:view') ||
      widget.session.can('stock:entries:create') ||
      widget.session.can('stock:entries:confirm');

  bool get _canWithdraw => widget.session.can('stock:withdraw');

  bool get _canCreateProduct => widget.session.can('products:create');

  Future<void> _openProductRegistration() async {
    final created = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          MobileProductFormSheet(api: _api, token: widget.session.token),
    );
    if (created != null && mounted) {
      setState(() => _message = 'Produto ${created.name} cadastrado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FB),
      appBar: AppBar(
        title: const Text('Lyncar App'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A66D8), Color(0xFF15C8D8)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061A38),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Color(0x33FFFFFF)),
                    ),
                    child: Image.asset(
                      'assets/brand/lyncar_logo_clean.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.session.companyName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Escolha a operação liberada para seu usuário.',
                          style: TextStyle(
                            color: Color(0xEFFFFFFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_message != null) ...[
              _MobileSuccessBox(message: _message!),
              const SizedBox(height: 12),
            ],
            if (_canCreateProduct)
              _MobileActionCard(
                icon: Icons.add_box_outlined,
                title: 'Cadastrar produto',
                subtitle:
                    'Criar produto direto no estoque da empresa conectada.',
                color: const Color(0xFF0F766E),
                onTap: _openProductRegistration,
              ),
            if (_canCreateProduct && (_canReceive || _canWithdraw))
              const SizedBox(height: 12),
            if (_canReceive)
              _MobileActionCard(
                icon: Icons.inventory_2_outlined,
                title: 'Recebimento de mercadorias',
                subtitle: 'Conferir entrada por câmera ou código manual.',
                color: const Color(0xFF0A66D8),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MobileReceivingScreen(session: widget.session),
                    ),
                  );
                },
              ),
            if (_canReceive && _canWithdraw) const SizedBox(height: 12),
            if (_canWithdraw)
              _MobileActionCard(
                icon: Icons.remove_shopping_cart_outlined,
                title: 'Baixa de estoque',
                subtitle: 'Registrar perda, vencimento ou consumo interno.',
                color: const Color(0xFFDC2626),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MobileStockWithdrawalScreen(session: widget.session),
                    ),
                  );
                },
              ),
            if (!_canCreateProduct && !_canReceive && !_canWithdraw)
              const _NoAppFunctionsCard(),
          ],
        ),
      ),
    );
  }
}

class _MobileSuccessBox extends StatelessWidget {
  const _MobileSuccessBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF065F46),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileActionCard extends StatelessWidget {
  const _MobileActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFD8E3F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoAppFunctionsCard extends StatelessWidget {
  const _NoAppFunctionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E3F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF64748B), size: 42),
          SizedBox(height: 10),
          Text(
            'Nenhuma função liberada no app',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'Peça para o administrador liberar Recebimento de mercadorias ou Baixa de estoque no cadastro do usuário.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

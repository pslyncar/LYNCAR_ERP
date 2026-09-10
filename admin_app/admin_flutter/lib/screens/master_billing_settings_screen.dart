import 'package:flutter/material.dart';

class MasterBillingSettingsScreen extends StatelessWidget {
  const MasterBillingSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configurações de cobrança',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF162640),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Estrutura preparada para centralizar regras financeiras sem misturar com a listagem.',
          style: TextStyle(color: Color(0xFF71839B)),
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SettingCard(
              icon: Icons.calendar_month_outlined,
              title: 'Geração mensal',
              detail: 'Define quando as mensalidades são criadas.',
            ),
            _SettingCard(
              icon: Icons.notifications_none_outlined,
              title: 'Lembretes',
              detail: 'Configura avisos antes e depois do vencimento.',
            ),
            _SettingCard(
              icon: Icons.percent_outlined,
              title: 'Juros e multa',
              detail: 'Regras para atualização do valor após o vencimento.',
            ),
            _SettingCard(
              icon: Icons.block_outlined,
              title: 'Inadimplência',
              detail: 'Políticas de acompanhamento e bloqueio.',
            ),
          ],
        ),
      ],
    ),
  );
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF176B93)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F3552),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF71839B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

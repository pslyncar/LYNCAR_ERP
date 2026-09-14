import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SalonEntryScreen extends StatefulWidget {
  const SalonEntryScreen({
    super.key,
    required this.slug,
    this.onAccountSelected,
  });

  final String slug;
  final void Function(String accountType, int accountNumber)? onAccountSelected;

  @override
  State<SalonEntryScreen> createState() => _SalonEntryScreenState();
}

class _SalonEntryScreenState extends State<SalonEntryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PedeOn salão')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 6
                : constraints.maxWidth >= 560
                ? 4
                : 3;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Contas do salão',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mesas e comandas usam a mesma conta. Selecione o número para lançar o pedido.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Escolha a mesa ou comanda',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: 30,
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    return Card(
                      key: Key('salon-account-$number'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openAccount(number),
                        child: Center(
                          child: Text(
                            'Mesa / comanda $number',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openAccount(int number) {
    final callback = widget.onAccountSelected;
    if (callback != null) {
      callback('mesa', number);
      return;
    }
    context.go('/${widget.slug}/salao/mesa/$number');
  }
}

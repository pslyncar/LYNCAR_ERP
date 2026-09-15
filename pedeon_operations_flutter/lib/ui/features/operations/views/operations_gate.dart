import 'package:flutter/material.dart';
import '../view_models/operations_view_model.dart';
import 'pairing_view.dart';
import 'operations_shell.dart';

class OperationsGate extends StatelessWidget {
  const OperationsGate({super.key, required this.viewModel});
  final OperationsViewModel viewModel;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) => switch (viewModel.phase) {
      OperationsPhase.starting => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      OperationsPhase.pairing => PairingView(viewModel: viewModel),
      OperationsPhase.ready => OperationsShell(viewModel: viewModel),
      OperationsPhase.failed => Scaffold(
        body: Center(child: Text(viewModel.error ?? 'Falha desconhecida.')),
      ),
    },
  );
}

import 'package:flutter/material.dart';
import '../data/repositories/operations_repository.dart';
import 'core/pedeon_theme.dart';
import 'features/operations/view_models/operations_view_model.dart';
import 'features/operations/views/operations_gate.dart';

class PedeOnOperationsApp extends StatefulWidget {
  const PedeOnOperationsApp({super.key, required this.repository});
  final OperationsRepository repository;
  @override
  State<PedeOnOperationsApp> createState() => _PedeOnOperationsAppState();
}

class _PedeOnOperationsAppState extends State<PedeOnOperationsApp> {
  late final OperationsViewModel viewModel;
  @override
  void initState() {
    super.initState();
    viewModel = OperationsViewModel(widget.repository)..initialize();
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PedeOn Operação',
    debugShowCheckedModeBanner: false,
    theme: buildPedeOnTheme(),
    home: OperationsGate(viewModel: viewModel),
  );
}

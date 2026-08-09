import 'package:flutter/material.dart';

class ResponsiveDataTable extends StatefulWidget {
  const ResponsiveDataTable({super.key, required this.child});

  final DataTable child;

  @override
  State<ResponsiveDataTable> createState() => _ResponsiveDataTableState();
}

class _ResponsiveDataTableState extends State<ResponsiveDataTable> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

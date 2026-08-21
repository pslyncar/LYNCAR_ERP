import 'package:flutter/material.dart';

class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.currentPage,
    required this.totalItems,
    required this.onPageChanged,
    this.pageSize = 20,
    this.itemLabel = 'registros',
  });

  final int currentPage;
  final int totalItems;
  final int pageSize;
  final String itemLabel;
  final ValueChanged<int> onPageChanged;

  int get _pageCount => totalItems == 0 ? 0 : (totalItems / pageSize).ceil();

  List<int?> _visiblePages() {
    final count = _pageCount;
    if (count <= 7) return [for (var index = 0; index < count; index++) index];
    final pages = <int>{0, count - 1};
    for (var index = currentPage - 1; index <= currentPage + 1; index++) {
      if (index > 0 && index < count - 1) pages.add(index);
    }
    final sorted = pages.toList()..sort();
    final result = <int?>[];
    for (var index = 0; index < sorted.length; index++) {
      if (index > 0 && sorted[index] - sorted[index - 1] > 1) {
        result.add(null);
      }
      result.add(sorted[index]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_pageCount <= 1) return const SizedBox.shrink();
    final safePage = currentPage.clamp(0, _pageCount - 1);
    final start = safePage * pageSize + 1;
    final end = (start + pageSize - 1).clamp(0, totalItems);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
              IconButton.outlined(
                key: const Key('app-pagination-previous'),
                tooltip: 'Página anterior',
                onPressed: safePage > 0
                    ? () => onPageChanged(safePage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              for (final page in _visiblePages())
                if (page == null)
                  const SizedBox(
                    width: 30,
                    height: 40,
                    child: Center(child: Text('…')),
                  )
                else
                  SizedBox(
                    width: 42,
                    height: 40,
                    child: page == safePage
                        ? FilledButton(
                            key: Key('app-pagination-page-${page + 1}'),
                            onPressed: null,
                            style: FilledButton.styleFrom(
                              disabledBackgroundColor: const Color(0xFF0E6680),
                              disabledForegroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                            ),
                            child: Text('${page + 1}'),
                          )
                        : OutlinedButton(
                            key: Key('app-pagination-page-${page + 1}'),
                            onPressed: () => onPageChanged(page),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: Text('${page + 1}'),
                          ),
                  ),
              IconButton.outlined(
                key: const Key('app-pagination-next'),
                tooltip: 'Próxima página',
                onPressed: safePage < _pageCount - 1
                    ? () => onPageChanged(safePage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
          final counter = Text(
            'Mostrando $start–$end de $totalItems $itemLabel',
            style: const TextStyle(color: Color(0xFF64748B)),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              children: [counter, const SizedBox(height: 10), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: counter),
              controls,
            ],
          );
        },
      ),
    );
  }
}

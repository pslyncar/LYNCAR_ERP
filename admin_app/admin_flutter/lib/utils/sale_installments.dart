class SaleInstallmentDraft {
  SaleInstallmentDraft({
    required this.number,
    required this.dueDate,
    required this.amountCents,
  });

  final int number;
  DateTime dueDate;
  int amountCents;
}

List<SaleInstallmentDraft> buildSaleInstallments({
  required int totalCents,
  required int count,
  required DateTime firstDueDate,
}) {
  final safeCount = count.clamp(1, 12);
  final base = totalCents ~/ safeCount;
  var remainder = totalCents % safeCount;
  return [
    for (var index = 0; index < safeCount; index++)
      SaleInstallmentDraft(
        number: index + 1,
        dueDate: addMonths(firstDueDate, index),
        amountCents: base + (remainder-- > 0 ? 1 : 0),
      ),
  ];
}

DateTime addMonths(DateTime date, int months) {
  final targetMonth = date.month + months;
  final year = date.year + ((targetMonth - 1) ~/ 12);
  final month = ((targetMonth - 1) % 12) + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(year, month, day);
}

String formatBrazilianDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

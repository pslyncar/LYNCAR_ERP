import 'package:flutter/services.dart';

class BrazilianMoneyInputFormatter extends TextInputFormatter {
  const BrazilianMoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return _emptyValue;
    final value = int.parse(digits) / 100;
    return _collapsed(formatBrazilianMoneyInput(value));
  }
}

class BrazilianDecimalInputFormatter extends TextInputFormatter {
  const BrazilianDecimalInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = newValue.text
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'[^0-9,]'), '');
    if (sanitized.isEmpty) return _emptyValue;
    final commaIndex = sanitized.indexOf(',');
    if (commaIndex < 0) return _collapsed(_groupInteger(sanitized));
    final integer = sanitized.substring(0, commaIndex);
    final decimals = sanitized.substring(commaIndex + 1).replaceAll(',', '');
    return _collapsed('${_groupInteger(integer)},$decimals');
  }
}

class BrazilianDateTimeInputFormatter extends TextInputFormatter {
  const BrazilianDateTimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return _emptyValue;
    final limited = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < limited.length; index++) {
      if (index == 2 || index == 4) buffer.write('/');
      if (index == 8) buffer.write(' ');
      if (index == 10) buffer.write(':');
      buffer.write(limited[index]);
    }
    return _collapsed(buffer.toString());
  }
}

class BrazilianDateInputFormatter extends TextInputFormatter {
  const BrazilianDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _limitDigits(newValue.text, 8);
    if (digits.isEmpty) return _emptyValue;
    return _collapsed(_applyMask(digits, '##/##/####'));
  }
}

class BrazilianCpfCnpjInputFormatter extends TextInputFormatter {
  const BrazilianCpfCnpjInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _limitDigits(newValue.text, 14);
    if (digits.isEmpty) return _emptyValue;
    if (digits.length <= 11) {
      return _collapsed(_applyMask(digits, '###.###.###-##'));
    }
    return _collapsed(_applyMask(digits, '##.###.###/####-##'));
  }
}

class BrazilianPhoneInputFormatter extends TextInputFormatter {
  const BrazilianPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _limitDigits(newValue.text, 11);
    if (digits.isEmpty) return _emptyValue;
    final mask = digits.length <= 10 ? '(##) ####-####' : '(##) #####-####';
    return _collapsed(_applyMask(digits, mask));
  }
}

class BrazilianCepInputFormatter extends TextInputFormatter {
  const BrazilianCepInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _limitDigits(newValue.text, 8);
    if (digits.isEmpty) return _emptyValue;
    return _collapsed(_applyMask(digits, '#####-###'));
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

double parseBrazilianNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  final onlyNumbers = trimmed.replaceAll(RegExp(r'[^0-9,.]'), '');
  final lastComma = onlyNumbers.lastIndexOf(',');
  final lastDot = onlyNumbers.lastIndexOf('.');
  final decimalIndex = lastComma > lastDot ? lastComma : lastDot;
  if (decimalIndex < 0) {
    return double.tryParse(onlyNumbers.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }
  final integerPart = onlyNumbers
      .substring(0, decimalIndex)
      .replaceAll(RegExp(r'[^0-9]'), '');
  final decimalPart = onlyNumbers
      .substring(decimalIndex + 1)
      .replaceAll(RegExp(r'[^0-9]'), '');
  return double.tryParse('$integerPart.$decimalPart') ?? 0;
}

String formatBrazilianDecimal(double value) {
  final fixed = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  final parts = fixed.split('.');
  return parts.length == 1
      ? _groupInteger(parts.first)
      : '${_groupInteger(parts.first)},${parts.last}';
}

String formatBrazilianMoneyInput(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  return '${_groupInteger(parts.first)},${parts.last}';
}

String _groupInteger(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) return '0';
  final buffer = StringBuffer();
  for (var index = 0; index < clean.length; index++) {
    final remaining = clean.length - index;
    buffer.write(clean[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}

TextEditingValue _collapsed(String text) {
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

const _emptyValue = TextEditingValue(
  text: '',
  selection: TextSelection.collapsed(offset: 0),
);

String _limitDigits(String value, int maxLength) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length > maxLength ? digits.substring(0, maxLength) : digits;
}

String _applyMask(String digits, String mask) {
  final buffer = StringBuffer();
  var digitIndex = 0;
  for (var index = 0; index < mask.length; index++) {
    if (digitIndex >= digits.length) break;
    final char = mask[index];
    if (char == '#') {
      buffer.write(digits[digitIndex]);
      digitIndex++;
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

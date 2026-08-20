import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/models/fiscal.dart';

void main() {
  group('FiscalNumberingStatus', () {
    test('carrega última e próxima numeração dos dois modelos', () {
      final status = FiscalNumberingStatus.fromJson(const {
        'environment': 'homologacao',
        'nfce_series': 1,
        'nfce_last_authorized_number': 71,
        'nfce_next_number': 72,
        'nfe_series': 1,
        'nfe_last_authorized_number': 12,
        'nfe_next_number': 13,
      });

      expect(status.nfceSeries, 1);
      expect(status.nfceLastAuthorizedNumber, 71);
      expect(status.nfceNextNumber, 72);
      expect(status.nfeSeries, 1);
      expect(status.nfeLastAuthorizedNumber, 12);
      expect(status.nfeNextNumber, 13);
    });

    test('mantém última autorizada vazia quando ainda não existe nota', () {
      final status = FiscalNumberingStatus.fromJson(const {});

      expect(status.nfceLastAuthorizedNumber, isNull);
      expect(status.nfeLastAuthorizedNumber, isNull);
      expect(status.nfceNextNumber, 1);
      expect(status.nfeNextNumber, 1);
    });
  });
}

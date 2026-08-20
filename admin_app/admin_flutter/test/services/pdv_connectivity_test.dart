import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/services/pdv_connectivity.dart';

void main() {
  group('PdvConnectivity', () {
    test('entra em contingência somente na primeira falha', () {
      final connectivity = PdvConnectivity();

      expect(
        connectivity.report(online: false),
        PdvConnectivityChange.enteredContingency,
      );
      expect(connectivity.inContingency, isTrue);
      expect(
        connectivity.report(online: false),
        PdvConnectivityChange.unchanged,
      );
    });

    test('detecta recuperação e remove a contingência', () {
      final connectivity = PdvConnectivity();
      connectivity.report(online: false);

      expect(
        connectivity.report(online: true),
        PdvConnectivityChange.recovered,
      );
      expect(connectivity.inContingency, isFalse);
      expect(connectivity.online, isTrue);
    });

    test('primeira conexão online não é tratada como recuperação', () {
      final connectivity = PdvConnectivity();

      expect(
        connectivity.report(online: true),
        PdvConnectivityChange.unchanged,
      );
      expect(connectivity.inContingency, isFalse);
    });
  });
}

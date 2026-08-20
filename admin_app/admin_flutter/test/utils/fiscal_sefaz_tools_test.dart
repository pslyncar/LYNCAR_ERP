import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/models/fiscal.dart';
import 'package:papezzosync_admin/utils/fiscal_sefaz_tools.dart';

CompanyFiscalSetting _setting(String environment, {bool certificate = true}) {
  return CompanyFiscalSetting(
    id: 1,
    environment: environment,
    nfceEnabled: true,
    pdvNfceEnabled: false,
    nfeEnabled: true,
    hasCertificate: certificate,
    nfceSeries: 1,
    nfceNextNumber: 1,
    nfeSeries: 1,
    nfeNextNumber: 1,
    hasNfceCsc: true,
  );
}

void main() {
  group('ferramentas SEFAZ', () {
    test('ficam disponíveis em homologação e produção', () {
      for (final environment in ['homologacao', 'producao']) {
        expect(
          canRunFiscalSefazTool(
            settings: _setting(environment),
            saving: false,
            working: false,
          ),
          isTrue,
        );
      }
    });

    test('continuam bloqueadas sem certificado ou durante processamento', () {
      expect(
        canRunFiscalSefazTool(
          settings: _setting('producao', certificate: false),
          saving: false,
          working: false,
        ),
        isFalse,
      );
      expect(
        canRunFiscalSefazTool(
          settings: _setting('producao'),
          saving: false,
          working: true,
        ),
        isFalse,
      );
    });

    test('mostra o ambiente fiscal real', () {
      expect(fiscalEnvironmentLabel('homologacao'), 'homologação');
      expect(fiscalEnvironmentLabel('producao'), 'produção');
    });
  });
}

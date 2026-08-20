import '../models/fiscal.dart';

bool canRunFiscalSefazTool({
  required CompanyFiscalSetting? settings,
  required bool saving,
  required bool working,
}) {
  final environment = settings?.environment;
  return !saving &&
      !working &&
      settings?.hasCertificate == true &&
      (environment == 'homologacao' || environment == 'producao');
}

String fiscalEnvironmentLabel(String environment) {
  return environment == 'producao' ? 'produção' : 'homologação';
}

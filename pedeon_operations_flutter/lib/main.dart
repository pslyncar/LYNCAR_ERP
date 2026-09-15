import 'package:flutter/material.dart';

import 'data/repositories/operations_repository.dart';
import 'data/services/edge_api_service.dart';
import 'data/services/terminal_credentials_store.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const edgeUrl = String.fromEnvironment(
    'LYNCAR_EDGE_URL',
    defaultValue: 'http://127.0.0.1:8765',
  );
  runApp(
    PedeOnOperationsApp(
      repository: OperationsRepository(
        edgeApi: EdgeApiService(baseUrl: Uri.parse(edgeUrl)),
        credentials: TerminalCredentialsStore(),
      ),
    ),
  );
}

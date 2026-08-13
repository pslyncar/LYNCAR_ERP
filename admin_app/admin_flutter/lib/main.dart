import 'package:flutter/material.dart';

import 'app.dart';
import 'screens/mercado_livre_callback_screen.dart';

void main() {
  final path = Uri.base.path.toLowerCase();
  if (path == '/marketplaces/mercado-livre/callback' ||
      path.endsWith('/marketplaces/mercado-livre/callback')) {
    runApp(const MercadoLivreCallbackApp());
    return;
  }
  runApp(const PapezzoSyncAdminApp());
}

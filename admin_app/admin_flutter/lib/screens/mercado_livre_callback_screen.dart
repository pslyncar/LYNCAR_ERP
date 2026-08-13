import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

class MercadoLivreCallbackApp extends StatelessWidget {
  const MercadoLivreCallbackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mercado Livre conectado',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MercadoLivreCallbackScreen(),
    );
  }
}

class MercadoLivreCallbackScreen extends StatefulWidget {
  const MercadoLivreCallbackScreen({super.key});

  @override
  State<MercadoLivreCallbackScreen> createState() =>
      _MercadoLivreCallbackScreenState();
}

class _MercadoLivreCallbackScreenState
    extends State<MercadoLivreCallbackScreen> {
  bool _loading = true;
  bool _success = false;
  String _message = 'Concluindo conexão com Mercado Livre...';

  @override
  void initState() {
    super.initState();
    unawaited(_finalizeConnection());
  }

  String get _apiBaseUrl {
    final host = Uri.base.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      );
    }
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.lyncar.com.br',
    );
  }

  Future<void> _finalizeConnection() async {
    final code = Uri.base.queryParameters['code'];
    final state = Uri.base.queryParameters['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      _setError('Retorno do Mercado Livre sem código de autorização.');
      return;
    }
    try {
      final uri = Uri.parse(
        '$_apiBaseUrl/marketplaces/mercado-livre/callback/finalize',
      ).replace(queryParameters: {'code': code, 'state': state});
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setError(_extractError(response));
        return;
      }
      web.window.localStorage.setItem(
        'lynkar_mercado_livre_connected_at',
        DateTime.now().toIso8601String(),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _message =
            'Mercado Livre conectado. Volte para a aba do LYNCAR; ela vai atualizar automaticamente.';
      });
      Timer(const Duration(seconds: 2), () {
        try {
          web.window.close();
        } catch (_) {
          // O navegador pode bloquear o fechamento quando a aba não foi aberta por script.
        }
      });
    } catch (_) {
      _setError('Não foi possível comunicar com o servidor LYNCAR.');
    }
  }

  String _extractError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Mantém a mensagem padrão abaixo.
    }
    return 'Não foi possível concluir a conexão com Mercado Livre.';
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071426), Color(0xFF0B2F57)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: const Color(0xFF0D2038),
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor:
                          (_success
                                  ? Colors.greenAccent
                                  : theme.colorScheme.primary)
                              .withValues(alpha: 0.14),
                      child: _loading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Icon(
                              _success
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 36,
                              color: _success
                                  ? Colors.greenAccent
                                  : theme.colorScheme.error,
                            ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _success
                          ? 'Mercado Livre conectado'
                          : 'Conexão Mercado Livre',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => web.window.close(),
                      child: const Text('Voltar para o LYNCAR'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

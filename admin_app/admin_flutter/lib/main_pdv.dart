import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import 'models/session.dart';
import 'screens/pdv_screen.dart';
import 'services/api_client.dart';
import 'services/app_session_storage.dart';
import 'services/pdv_auto_update_service.dart';

const _defaultPdvApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.lyncar.com.br',
);
const _pdvAppEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'production',
);
const _pdvWindowsVersion = String.fromEnvironment(
  'PDV_APP_VERSION',
  defaultValue: '1.0.14',
);
bool get _isPdvTestArea => _pdvAppEnvironment.toLowerCase() == 'test';
const _defaultPdvCompanyCode = String.fromEnvironment(
  'COMPANY_CODE',
  defaultValue: 'drika_padaria',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    fullScreen: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(false);
  runApp(const LynCarPdvApp());
}

class LynCarPdvApp extends StatelessWidget {
  const LynCarPdvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDV Lyncar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A66D8),
          primary: const Color(0xFF0A66D8),
          secondary: const Color(0xFF15C8D8),
        ),
        textTheme: GoogleFonts.interTextTheme().apply(
          bodyColor: const Color(0xFF132033),
          displayColor: const Color(0xFF132033),
        ),
        scaffoldBackgroundColor: const Color(0xFF07111F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF07111F),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF135A77),
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        useMaterial3: true,
      ),
      home: const _PdvTerminalGate(),
    );
  }
}

class _PdvTerminalConfig {
  const _PdvTerminalConfig({
    required this.apiBaseUrl,
    required this.companyCode,
    required this.email,
    required this.password,
  });

  final String apiBaseUrl;
  final String companyCode;
  final String email;
  final String password;

  factory _PdvTerminalConfig.fromJson(Map<String, dynamic> json) {
    final storedApiBaseUrl = json['apiBaseUrl']?.toString() ?? '';
    final storedCompanyCode = json['companyCode']?.toString() ?? '';
    return _PdvTerminalConfig(
      apiBaseUrl: !_isPdvTestArea
          ? _defaultPdvApiBaseUrl
          : (storedApiBaseUrl.isEmpty
                ? _defaultPdvApiBaseUrl
                : storedApiBaseUrl),
      companyCode: _isPdvTestArea && storedCompanyCode.trim().isEmpty
          ? _defaultPdvCompanyCode
          : storedCompanyCode,
      email: json['email']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': _isPdvTestArea ? apiBaseUrl.trim() : _defaultPdvApiBaseUrl,
      'companyCode': companyCode.trim().toLowerCase(),
      'email': email.trim(),
      'password': password,
    };
  }

  bool get isComplete {
    return apiBaseUrl.trim().isNotEmpty &&
        (!_isPdvTestArea || companyCode.trim().isNotEmpty) &&
        email.trim().isNotEmpty &&
        password.isNotEmpty;
  }
}

class _PdvTerminalGate extends StatefulWidget {
  const _PdvTerminalGate();

  @override
  State<_PdvTerminalGate> createState() => _PdvTerminalGateState();
}

class _PdvTerminalGateState extends State<_PdvTerminalGate>
    with WindowListener {
  static const _configKey = 'lyncar.pdv.terminal.config';
  static const _sessionKey = 'lyncar.pdv.session';

  final _storage = AppSessionStorage();
  Session? _session;
  _PdvTerminalConfig? _config;
  bool _ready = false;
  bool _connecting = false;
  bool _fullscreen = true;
  bool _windowControlsVisible = false;
  bool _windowTransitioning = false;
  bool _returnToFullscreenAfterRestore = false;
  bool _cashOpen = false;
  bool _checkingUpdate = false;
  bool _updateDialogOpen = false;
  double? _updateDownloadProgress;
  String _updateProgressText = 'Preparando atualização...';
  VoidCallback? _updateDialogRefresh;
  Timer? _sessionRefreshTimer;
  PdvUpdateInfo? _pendingUpdate;
  String? _error;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _restoreTerminal();
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_cashOpen) {
      await windowManager.setPreventClose(true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feche o caixa antes de sair do PDV.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullscreen = false);
  }

  @override
  void onWindowMinimize() {
    if (mounted) setState(() => _windowControlsVisible = false);
  }

  @override
  Future<void> onWindowRestore() async {
    if (!_returnToFullscreenAfterRestore) return;
    _returnToFullscreenAfterRestore = false;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await _setFullscreen(true);
  }

  Future<void> _setCashOpen(bool value) async {
    if (mounted) setState(() => _cashOpen = value);
    await windowManager.setPreventClose(value);
    if (!value) {
      final pending = _pendingUpdate;
      if (pending != null) {
        await _offerPdvUpdate(pending, fromPending: true);
      } else if (_session != null) {
        unawaited(_checkForPdvUpdate(silent: true));
      }
    }
  }

  Future<void> _setFullscreen(bool value) async {
    if (_windowTransitioning) return;
    _windowTransitioning = true;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await windowManager.setFullScreen(value);
      if (!value) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await windowManager.maximize();
      }
      if (mounted) {
        setState(() {
          _fullscreen = value;
          _windowControlsVisible = false;
        });
      }
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> _minimizeWindow() async {
    if (_windowTransitioning) return;
    _windowTransitioning = true;
    try {
      final wasFullscreen = await windowManager.isFullScreen();
      _returnToFullscreenAfterRestore = wasFullscreen;
      if (wasFullscreen) {
        await windowManager.setFullScreen(false);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await windowManager.minimize();
      if (mounted) setState(() => _windowControlsVisible = false);
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> _restoreTerminal() async {
    final rawConfig = await _storage.read(_configKey);
    final config = _decodeConfig(rawConfig);
    final rawSession = await _storage.read(_sessionKey);
    final session = _decodeSession(rawSession);
    if (mounted) {
      setState(() {
        _config = config;
        _session = session;
        _ready = true;
      });
    }
    if (_session != null) {
      _startSessionRefreshTimer();
      await _refreshPdvSessionIfNeeded(force: true);
      unawaited(_checkForPdvUpdate(silent: true));
    } else if (config?.isComplete == true) {
      await _connectTerminal(config!);
    }
  }

  _PdvTerminalConfig? _decodeConfig(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return _PdvTerminalConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Session? _decodeSession(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Session.fromStorageJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveConfig(_PdvTerminalConfig config) async {
    await _storage.write(_configKey, jsonEncode(config.toJson()));
    await _storage.remove(_sessionKey);
    if (mounted) {
      setState(() {
        _config = config;
        _session = null;
      });
    }
    await _connectTerminal(config);
  }

  Future<void> _storeSession(Session session) async {
    await _storage.write(_sessionKey, jsonEncode(session.toStorageJson()));
    if (mounted) setState(() => _session = session);
    _startSessionRefreshTimer();
  }

  void _startSessionRefreshTimer() {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(_refreshPdvSessionIfNeeded());
    });
  }

  Future<bool> _refreshPdvSessionIfNeeded({bool force = false}) async {
    final session = _session;
    if (session == null) return false;
    if (!force && !session.tokenExpiresWithin(const Duration(minutes: 30))) {
      return true;
    }
    try {
      final refreshed = await ApiClient(session.apiBaseUrl).refreshPdvSession(
        session,
      );
      if (refreshed.isMasterCompany || !refreshed.can('sales:create')) {
        throw ApiException('Sessao do PDV sem permissao para operar caixa.');
      }
      await _storeSession(refreshed);
      if (mounted && (_error?.contains('Sessao') ?? false)) {
        setState(() => _error = null);
      }
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _storage.remove(_sessionKey);
        _sessionRefreshTimer?.cancel();
        if (mounted) {
          setState(() {
            _session = null;
            _error = 'Sessao do PDV expirada. Entre novamente.';
          });
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _connectTerminal(_PdvTerminalConfig config) async {
    if (!config.isComplete) {
      setState(() => _error = 'Configure este terminal antes de abrir o PDV.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final api = ApiClient(config.apiBaseUrl);
      final session = _isPdvTestArea
          ? await api.login(
              companyCode: config.companyCode,
              email: config.email,
              password: config.password,
            )
          : await api.loginAutomatically(
              email: config.email,
              password: config.password,
              clientType: 'pdv_windows',
            );
      if (session.isMasterCompany) {
        throw ApiException(
          'Configure o PDV Windows com a empresa cliente, nao com o master.',
        );
      }
      if (!session.can('sales:create')) {
        throw ApiException(
          'O usuario configurado nao tem acesso para operar o PDV.',
        );
      }
      await _storeSession(session);
      unawaited(_checkForPdvUpdate(silent: true));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Nao foi possivel conectar este terminal ao servidor. ${_terminalConnectionErrorMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _terminalConnectionErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('Failed host lookup')) {
      return 'Verifique a internet ou DNS da maquina.';
    }
    if (message.contains('CERTIFICATE') ||
        message.contains('HandshakeException') ||
        message.contains('TLS')) {
      return 'Verifique data/hora do Windows e certificados/TLS.';
    }
    if (message.contains('Connection refused')) {
      return 'O endereco da API recusou conexao. Confira o servidor.';
    }
    if (message.contains('timed out') || message.contains('Timeout')) {
      return 'A conexao demorou demais. Verifique internet/firewall.';
    }
    return message;
  }

  PdvAutoUpdateService _autoUpdateService(Session session) {
    return PdvAutoUpdateService(
      apiBaseUrl: session.apiBaseUrl,
      token: session.token,
      currentVersion: _pdvWindowsVersion,
      channel: _isPdvTestArea ? 'test' : 'stable',
      terminalId: _terminalId(session),
    );
  }

  String _terminalId(Session session) {
    final company = session.companyCode.trim().isEmpty
        ? 'empresa'
        : session.companyCode.trim().toLowerCase();
    final user = session.userId?.toString() ?? 'usuario';
    final machine = Platform.localHostname.trim().isEmpty
        ? 'terminal'
        : Platform.localHostname.trim().toLowerCase();
    return '$company|$user|$machine';
  }

  Future<void> _checkForPdvUpdate({required bool silent}) async {
    var session = _session;
    if (session == null ||
        _checkingUpdate ||
        _updateDialogOpen ||
        !Platform.isWindows) {
      return;
    }
    _checkingUpdate = true;
    try {
      await _refreshPdvSessionIfNeeded();
      session = _session;
      if (session == null) return;
      final update = await _autoUpdateService(session).check();
      if (update == null) return;
      _pendingUpdate = update;
      if (_cashOpen) return;
      await _offerPdvUpdate(update);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível verificar atualização do PDV.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _checkingUpdate = false;
    }
  }

  Future<void> _offerPdvUpdate(
    PdvUpdateInfo update, {
    bool fromPending = false,
  }) async {
    if (!mounted || _updateDialogOpen || _cashOpen) return;
    _updateDialogOpen = true;
    try {
      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (context) => AlertDialog(
          title: Text(
            update.mandatory
                ? 'Atualização obrigatória do PDV'
                : 'Nova versão do PDV disponível',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  update.message?.trim().isNotEmpty == true
                      ? update.message!.trim()
                      : 'Versão ${update.version} disponível para instalação.',
                ),
                if (update.releaseNotes?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    update.releaseNotes!.trim(),
                    style: const TextStyle(color: Color(0xFF475569)),
                  ),
                ],
                if (fromPending) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'O caixa está fechado agora, então é seguro atualizar.',
                    style: TextStyle(color: Color(0xFF0F766E)),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'O PDV será fechado, atualizado e aberto novamente ao final.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          actions: [
            if (!update.mandatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Depois'),
              ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Atualizar agora'),
            ),
          ],
        ),
      );
      if (shouldInstall == true) {
        await _downloadAndInstallPdvUpdate(update);
      } else if (!update.mandatory) {
        _pendingUpdate = update;
      }
    } finally {
      _updateDialogOpen = false;
    }
  }

  Future<void> _downloadAndInstallPdvUpdate(PdvUpdateInfo update) async {
    final session = _session;
    if (session == null || _cashOpen) return;
    setState(() {
      _updateDownloadProgress = null;
      _updateProgressText = 'Preparando atualização...';
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          void refreshDialog() {
            if (context.mounted) setDialogState(() {});
          }

          _updateDialogRefresh = refreshDialog;
          final progress = _updateDownloadProgress;
          final percent = progress == null
              ? null
              : (progress.clamp(0, 1) * 100).toStringAsFixed(0);
          return AlertDialog(
            title: const Text('Atualizando PDV'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 14),
                  Text(
                    percent == null
                        ? _updateProgressText
                        : '$_updateProgressText $percent%',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Não desligue o computador. O PDV será reaberto automaticamente ao final.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    try {
      final service = _autoUpdateService(session);
      void setProgress(String text, [double? value]) {
        _updateProgressText = text;
        _updateDownloadProgress = value;
        _updateDialogRefresh?.call();
      }

      setProgress('Baixando atualização...', null);
      final installer = await service.downloadAndValidate(
        update,
        onProgress: (received, total) {
          if (total == null || total <= 0) {
            setProgress('Baixando atualização...', null);
          } else {
            setProgress('Baixando atualização...', received / total);
          }
        },
      );
      setProgress('Validando arquivo...', 1);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      setProgress('Fechando PDV para aplicar atualização...', 1);
      await service.installAfterExit(installer);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      }
    } on PdvUpdateException catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível instalar a atualização do PDV.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _updateDialogRefresh = null;
    }
  }

  Future<void> _openConfig() async {
    final saved = await showDialog<_PdvTerminalConfig>(
      context: context,
      barrierDismissible: _session != null,
      builder: (context) => _TerminalConfigDialog(config: _config),
    );
    if (saved != null) {
      await _saveConfig(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const _TerminalStatusScreen(message: 'Carregando terminal...');
    }

    final config = _config;
    final session = _session;
    if (config == null || !config.isComplete) {
      return _TerminalStatusScreen(
        message: 'ENTRAR NO PDV LYNCAR',
        detail: 'Use o mesmo e-mail e senha cadastrados no sistema Lyncar.',
        error: _error,
        primaryLabel: 'Entrar',
        onPrimary: _openConfig,
      );
    }

    if (_connecting || session == null) {
      return _TerminalStatusScreen(
        message: _connecting ? 'Conectando terminal...' : 'CAIXA FECHADO',
        detail: _isPdvTestArea
            ? 'Empresa ${config.companyCode}. O caixa abre somente com fiscal e operador.'
            : 'A empresa será identificada automaticamente pelo seu e-mail.',
        error: _error,
        primaryLabel: _connecting ? null : 'Reconectar',
        onPrimary: _connecting ? null : () => _connectTerminal(config),
        secondaryLabel: 'Trocar acesso',
        onSecondary: _openConfig,
      );
    }

    return Stack(
      children: [
        PdvScreen(
          session: session,
          fullscreen: _fullscreen,
          windowsAppMode: true,
          onEnsurePdvToken: () async {
            final ok = await _refreshPdvSessionIfNeeded(force: true);
            return ok ? _session?.token : null;
          },
          onPdvCashOpenChanged: _setCashOpen,
          onPdvFullscreenChanged: _setFullscreen,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 8,
          child: MouseRegion(
            opaque: true,
            onEnter: (_) => setState(() => _windowControlsVisible = true),
            child: const SizedBox.expand(),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          top: _windowControlsVisible ? 0 : -48,
          right: 0,
          child: MouseRegion(
            onExit: (_) => setState(() => _windowControlsVisible = false),
            child: Material(
              color: const Color(0xEE07111F),
              elevation: 12,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Minimizar',
                    onPressed: _windowTransitioning ? null : _minimizeWindow,
                    color: Colors.white,
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: _fullscreen
                        ? 'Sair da tela cheia'
                        : 'Entrar em tela cheia',
                    onPressed: () => _setFullscreen(!_fullscreen),
                    color: Colors.white,
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar aplicativo',
                    onPressed: windowManager.close,
                    color: const Color(0xFFFCA5A5),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TerminalStatusScreen extends StatelessWidget {
  const _TerminalStatusScreen({
    required this.message,
    this.detail,
    this.error,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final String? detail;
  final String? error;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/brand/lyncar_logo_clean.png',
                  width: 260,
                  height: 92,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 16,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (primaryLabel != null || secondaryLabel != null) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (secondaryLabel != null)
                        OutlinedButton.icon(
                          onPressed: onSecondary,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(secondaryLabel!),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      if (primaryLabel != null)
                        FilledButton.icon(
                          onPressed: onPrimary,
                          icon: const Icon(Icons.keyboard_return),
                          label: Text(primaryLabel!),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalConfigDialog extends StatefulWidget {
  const _TerminalConfigDialog({this.config});

  final _PdvTerminalConfig? config;

  @override
  State<_TerminalConfigDialog> createState() => _TerminalConfigDialogState();
}

class _TerminalConfigDialogState extends State<_TerminalConfigDialog> {
  late final TextEditingController _api;
  late final TextEditingController _company;
  late final TextEditingController _email;
  late final TextEditingController _password;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _api = TextEditingController(
      text: _isPdvTestArea
          ? (config?.apiBaseUrl ?? _defaultPdvApiBaseUrl)
          : _defaultPdvApiBaseUrl,
    );
    _company = TextEditingController(
      text:
          config?.companyCode ?? (_isPdvTestArea ? _defaultPdvCompanyCode : ''),
    );
    _email = TextEditingController(text: config?.email ?? '');
    _password = TextEditingController(text: config?.password ?? '');
  }

  @override
  void dispose() {
    _api.dispose();
    _company.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    final config = _PdvTerminalConfig(
      apiBaseUrl: _isPdvTestArea ? _api.text.trim() : _defaultPdvApiBaseUrl,
      companyCode: _company.text.trim().toLowerCase(),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!config.isComplete) {
      setState(
        () => _error = _isPdvTestArea
            ? 'Preencha servidor, empresa, e-mail e senha.'
            : 'Preencha seu e-mail e senha.',
      );
      return;
    }
    if (_isPdvTestArea && config.companyCode == 'master') {
      setState(
        () => _error = 'PDV Windows deve usar a empresa cliente, nao o master.',
      );
      return;
    }
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entrar no PDV Lyncar'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isPdvTestArea
                  ? 'Área de teste: informe o servidor, a empresa e o acesso que deseja validar.'
                  : 'Informe o mesmo e-mail e senha usados no sistema Lyncar. A empresa será localizada automaticamente.',
              style: TextStyle(color: Color(0xFF475569), height: 1.35),
            ),
            const SizedBox(height: 16),
            if (_isPdvTestArea) ...[
              TextField(
                controller: _api,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Servidor API',
                  hintText: 'http://127.0.0.1:8000',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _company,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Empresa',
                  hintText: 'ex: padaria_centro',
                  prefixIcon: Icon(Icons.apartment_outlined),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Senha',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.login),
          label: const Text('Entrar'),
        ),
      ],
    );
  }
}

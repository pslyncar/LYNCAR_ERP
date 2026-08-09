import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/session.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/mobile_app_dashboard_screen.dart';
import 'screens/mobile_app_login_screen.dart';
import 'services/api_client.dart';
import 'services/app_session_storage.dart';
import 'services/session_storage.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class PapezzoSyncAdminApp extends StatelessWidget {
  const PapezzoSyncAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Lyncar',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _PapezzoScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A66D8),
          brightness: Brightness.light,
          primary: const Color(0xFF0A66D8),
          secondary: const Color(0xFF15C8D8),
          surface: Colors.white,
          surfaceContainerHighest: const Color(0xFFE8EEF7),
        ),
        textTheme: GoogleFonts.interTextTheme().apply(
          bodyColor: const Color(0xFF132033),
          displayColor: const Color(0xFF132033),
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F6FB),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE1E7F0),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          labelStyle: const TextStyle(
            color: Color(0xFF53657D),
            fontWeight: FontWeight.w600,
          ),
          hintStyle: const TextStyle(color: Color(0xFF7B8AA1)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFCBD6E4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF0A66D8), width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
          ),
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
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF334155),
            side: const BorderSide(color: Color(0xFFCBD6E4)),
            minimumSize: const Size(44, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: Color(0xFFCBD6E4)),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF334155),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFFEAF2FF),
          selectedColor: Color(0xFFDDF7F9),
          side: BorderSide(color: Color(0xFFCBD6E4)),
          labelStyle: TextStyle(
            color: Color(0xFF334155),
            fontWeight: FontWeight.w600,
          ),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(false),
          trackVisibility: const WidgetStatePropertyAll(false),
          thickness: const WidgetStatePropertyAll(8),
          radius: const Radius.circular(8),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.dragged) ||
                states.contains(WidgetState.hovered)) {
              return const Color(0xFF64748B);
            }
            return const Color(0xFF94A3B8);
          }),
          trackColor: const WidgetStatePropertyAll(Color(0xFFE2E8F0)),
        ),
        dataTableTheme: const DataTableThemeData(
          horizontalMargin: 14,
          columnSpacing: 24,
          headingRowColor: WidgetStatePropertyAll(Color(0xFFF5F8FC)),
          headingTextStyle: TextStyle(
            color: Color(0xFF26364A),
            fontWeight: FontWeight.w900,
          ),
          dataTextStyle: TextStyle(color: Color(0xFF26364A)),
          dividerThickness: 0.7,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFF7FAFD),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class _PapezzoScrollBehavior extends MaterialScrollBehavior {
  const _PapezzoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _sessionKey = 'papezzosync.session';
  static const _lastActivityKey = 'papezzosync.lastActivity';
  static const _pdvCashSessionKey = 'papezzosync.pdv.cashSession';
  static const _siteInactivityTimeout = Duration(hours: 8);
  static const _activityWriteInterval = Duration(seconds: 15);
  static const _tokenRefreshWindow = Duration(minutes: 10);

  final _storage = AppSessionStorage();
  final _legacyStorage = BrowserSessionStorage();
  Session? _session;
  bool _ready = false;
  bool _pdvCashOpen = false;
  bool _refreshingSession = false;
  Timer? _sessionTimer;
  DateTime? _lastActivityWriteAt;
  final _activityFocusNode = FocusNode(debugLabel: 'activity-listener');

  bool get _mobileAppMode {
    if (kIsWeb) {
      final uri = Uri.base;
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();
      final forcedByQuery =
          uri.queryParameters['app'] == '1' ||
          uri.queryParameters['mobile'] == '1';
      return host == 'app.lyncar.com.br' ||
          host.startsWith('app.') ||
          path == '/app' ||
          path.startsWith('/app/') ||
          forcedByQuery;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _usesInactivityTimeout => kIsWeb && !_mobileAppMode;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
    _sessionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_maintainSession()),
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _activityFocusNode.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final rawSession = await _storage.read(_sessionKey);
    final lastActivity = await _readLastActivity();

    final hasOpenPdvCash = _hasOpenPdvCashSession();
    if (rawSession == null ||
        lastActivity == null ||
        (_usesInactivityTimeout &&
            DateTime.now().toUtc().difference(lastActivity) >
                _siteInactivityTimeout &&
            !hasOpenPdvCash)) {
      await _clearStoredSession();
      if (mounted) setState(() => _ready = true);
      return;
    }

    try {
      final data = jsonDecode(rawSession) as Map<String, dynamic>;
      var session = Session.fromStorageJson(data);
      if (session.isTokenExpired) {
        await _clearStoredSession();
        if (mounted) setState(() => _ready = true);
        return;
      }
      try {
        session = await ApiClient(session.apiBaseUrl).refreshSession(session);
        unawaited(_storeSession(session));
      } catch (_) {
        // Mantem a sessao local quando o refresh falha por conexao temporaria.
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _pdvCashOpen = hasOpenPdvCash;
        _ready = true;
      });
      unawaited(_touchActivity());
      unawaited(_sendHeartbeat(session));
    } catch (_) {
      await _clearStoredSession();
      if (mounted) setState(() => _ready = true);
    }
  }

  void _setSession(Session session) {
    unawaited(_storeSession(session));
    setState(() => _session = session);
    unawaited(_touchActivity());
    unawaited(_sendHeartbeat(session));
  }

  Future<void> _storeSession(Session session) {
    return _storage.write(_sessionKey, jsonEncode(session.toStorageJson()));
  }

  void _logout() {
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    unawaited(_clearStoredSession());
    setState(() {
      _session = null;
      _pdvCashOpen = false;
    });
  }

  Future<void> _clearStoredSession() async {
    await Future.wait([
      _storage.remove(_sessionKey),
      _storage.remove(_lastActivityKey),
    ]);
  }

  Future<void> _touchActivity() async {
    if (_session == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final lastWrite = _lastActivityWriteAt;
    if (lastWrite != null &&
        now.difference(lastWrite) < _activityWriteInterval) {
      return;
    }
    _lastActivityWriteAt = now;
    await _storage.write(_lastActivityKey, now.toIso8601String());
  }

  Future<DateTime?> _readLastActivity() async {
    final value = await _storage.read(_lastActivityKey);
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  bool _hasOpenPdvCashSession() {
    final value = _legacyStorage.read(_pdvCashSessionKey);
    if (value == null) {
      return false;
    }
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      return data['cash_open'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maintainSession() async {
    final session = _session;
    if (session == null) {
      return;
    }
    unawaited(_sendHeartbeat(session));
    if (!session.isTokenExpired &&
        session.tokenExpiresWithin(_tokenRefreshWindow)) {
      await _refreshSessionIfPossible();
    }
    if ((_pdvCashOpen || _hasOpenPdvCashSession()) && !session.isTokenExpired) {
      await _touchActivity();
      return;
    }
    var inactive = false;
    if (_usesInactivityTimeout) {
      final lastActivity = await _readLastActivity();
      inactive =
          lastActivity == null ||
          DateTime.now().toUtc().difference(lastActivity) >
              _siteInactivityTimeout;
    }
    if (inactive || session.isTokenExpired) {
      _logout();
    }
  }

  Future<void> _sendHeartbeat(Session session) async {
    if (session.isTokenExpired || session.isMasterCompany) {
      return;
    }
    try {
      await ApiClient(
        session.apiBaseUrl,
      ).heartbeat(session.token, clientType: _mobileAppMode ? 'app' : 'web');
    } catch (_) {
      // Presenca online e informativa; falha temporaria nao derruba a sessao.
    }
  }

  Future<void> _refreshSessionIfPossible() async {
    if (_refreshingSession) {
      return;
    }
    final current = _session;
    if (current == null || current.isTokenExpired) {
      return;
    }
    _refreshingSession = true;
    try {
      final refreshed = await ApiClient(
        current.apiBaseUrl,
      ).refreshSession(current);
      if (!mounted) return;
      await _storeSession(refreshed);
      setState(() => _session = refreshed);
      await _touchActivity();
    } catch (_) {
      // Falha temporaria de rede/API nao deve derrubar o usuario antes do token vencer.
    } finally {
      _refreshingSession = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (!_ready) {
      content = const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    } else {
      final session = _session;
      if (session == null) {
        content = _mobileAppMode
            ? MobileAppLoginScreen(onLogin: _setSession)
            : LoginScreen(onLogin: _setSession);
      } else if (_mobileAppMode) {
        if (!session.can('app:access')) {
          unawaited(_clearStoredSession());
          content = MobileAppLoginScreen(onLogin: _setSession);
        } else {
          content = MobileAppDashboardScreen(
            session: session,
            onLogout: _logout,
          );
        }
      } else {
        content = AppShell(
          session: session,
          onLogout: _logout,
          onPdvCashOpenChanged: (open) {
            if (_pdvCashOpen == open) return;
            setState(() => _pdvCashOpen = open);
            if (open) unawaited(_touchActivity());
          },
        );
      }
    }

    return Focus(
      focusNode: _activityFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        unawaited(_touchActivity());
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => unawaited(_touchActivity()),
        onPointerMove: (_) => unawaited(_touchActivity()),
        onPointerHover: (_) => unawaited(_touchActivity()),
        onPointerSignal: (_) => unawaited(_touchActivity()),
        child: content,
      ),
    );
  }
}

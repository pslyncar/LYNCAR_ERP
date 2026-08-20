import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class PdvSyncChannel {
  PdvSyncChannel({
    required this.baseUrl,
    required this.token,
    required this.onCursor,
    this.onConnectionChanged,
  });

  final String baseUrl;
  final String token;
  final void Function(int cursor) onCursor;
  final void Function(bool connected)? onConnectionChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _pingTimer;
  bool _disposed = false;
  bool? _connected;
  int _attempt = 0;

  void connect() {
    if (_disposed || _channel != null) return;
    final httpUri = Uri.parse(baseUrl);
    final uri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: '${httpUri.path.replaceFirst(RegExp(r'/$'), '')}/pdv/sync/ws',
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _reconnect(),
        onDone: _reconnect,
        cancelOnError: true,
      );
      unawaited(
        channel.ready.then<void>((_) {
          if (_disposed || _channel != channel) return;
          _attempt = 0;
          channel.sink.add(jsonEncode({'token': token}));
          _pingTimer?.cancel();
          _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
            try {
              channel.sink.add('ping');
            } catch (_) {
              _reconnect();
            }
          });
        }, onError: (Object _, StackTrace _) => _reconnect()),
      );
    } catch (_) {
      _reconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    if (raw == 'pong') {
      _setConnected(true);
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cursor = (data['cursor'] as num?)?.toInt();
      if (data['type'] == 'sync' && cursor != null) {
        _setConnected(true);
        onCursor(cursor);
      }
    } catch (_) {
      // Mensagem desconhecida nao interrompe a sincronizacao.
    }
  }

  void _reconnect() {
    if (_disposed) return;
    _setConnected(false);
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _retryTimer?.cancel();
    final seconds = switch (_attempt) {
      0 => 1,
      1 => 2,
      2 => 4,
      3 => 8,
      _ => 30,
    };
    _attempt += 1;
    _retryTimer = Timer(Duration(seconds: seconds), connect);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChanged?.call(value);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}

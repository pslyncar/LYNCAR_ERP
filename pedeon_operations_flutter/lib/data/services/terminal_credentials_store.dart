import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TerminalCredentialsStore {
  TerminalCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const _tokenKey = 'lyncar_edge_terminal_token';
  final FlutterSecureStorage _storage;
  Future<String?> readToken() => _storage.read(key: _tokenKey);
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  Future<void> clear() => _storage.delete(key: _tokenKey);
}

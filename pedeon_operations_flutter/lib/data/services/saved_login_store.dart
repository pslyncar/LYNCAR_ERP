import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedLogin {
  const SavedLogin({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'password': password};

  factory SavedLogin.fromJson(Map<String, dynamic> json) => SavedLogin(
    email: '${json['email'] ?? ''}',
    password: '${json['password'] ?? ''}',
  );
}

class SavedLoginStore {
  SavedLoginStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'pedeon_saved_logins';
  final FlutterSecureStorage _storage;

  Future<List<SavedLogin>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedLogin.fromJson)
          .where((item) => item.email.isNotEmpty && item.password.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(SavedLogin login) async {
    final current = await read();
    final updated = [
      login,
      ...current.where((item) => item.email.toLowerCase() != login.email.toLowerCase()),
    ];
    await _storage.write(
      key: _key,
      value: jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> remove(String email) async {
    final updated = (await read())
        .where((item) => item.email.toLowerCase() != email.toLowerCase())
        .toList(growable: false);
    if (updated.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(
        key: _key,
        value: jsonEncode(updated.map((item) => item.toJson()).toList()),
      );
    }
  }
}

import 'package:shared_preferences/shared_preferences.dart';

class AppSessionStorage {
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _store async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<String?> read(String key) async {
    final store = await _store;
    return store.getString(key);
  }

  Future<void> write(String key, String value) async {
    final store = await _store;
    await store.setString(key, value);
  }

  Future<void> remove(String key) async {
    final store = await _store;
    await store.remove(key);
  }
}

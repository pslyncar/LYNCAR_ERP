// ignore_for_file: avoid_web_libraries_in_flutter

// ignore: deprecated_member_use
import 'dart:html' as html;

class BrowserSessionStorage {
  String? read(String key) => html.window.localStorage[key];

  void write(String key, String value) {
    html.window.localStorage[key] = value;
  }

  void remove(String key) {
    html.window.localStorage.remove(key);
  }
}

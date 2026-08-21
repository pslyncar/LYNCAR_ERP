// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void redirectToUrl(String url, {bool newTab = false}) {
  if (newTab) {
    html.AnchorElement(href: url)
      ..target = '_blank'
      ..rel = 'noopener noreferrer'
      ..click();
    return;
  }
  html.window.location.href = url;
}

void writeBrowserStorage(String key, String value) {
  html.window.localStorage[key] = value;
}

void closeBrowserWindow() {
  html.window.close();
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain;charset=utf-8',
}) {
  final blob = html.Blob([content], mimeType);
  _downloadBlob(filename, blob);
}

void downloadBytesFile({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/octet-stream',
}) {
  final blob = html.Blob([bytes], mimeType);
  _downloadBlob(filename, blob);
}

void _downloadBlob(String filename, html.Blob blob) {
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

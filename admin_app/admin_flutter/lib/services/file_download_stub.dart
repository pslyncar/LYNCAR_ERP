void downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain;charset=utf-8',
}) {}

void downloadBytesFile({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/octet-stream',
}) {}

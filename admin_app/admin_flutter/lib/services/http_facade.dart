import 'dart:convert';

import 'package:http/http.dart' as package_http;

import 'http_transport.dart';

export 'package:http/http.dart' hide delete, get, patch, post, put;

final package_http.Client _client = createHttpClient();
String? _csrfToken;

void updateCsrfToken(String? value) {
  if (value != null && value.isNotEmpty) {
    _csrfToken = value;
  }
}

Map<String, String>? _headers(Map<String, String>? headers) {
  if (_csrfToken == null) return headers;
  return {...?headers, 'X-CSRF-Token': _csrfToken!};
}

/// Sends multipart requests through the same browser client used by the
/// regular API calls. This is important on web: the shared BrowserClient is
/// configured with credentials enabled, so the HttpOnly web session cookie is
/// included during image/file uploads as well.
Future<package_http.StreamedResponse> sendMultipart(
  package_http.BaseRequest request,
) {
  if (_csrfToken != null) {
    request.headers['X-CSRF-Token'] = _csrfToken!;
  }
  return _client.send(request);
}

Future<package_http.Response> get(
  Uri url, {
  Map<String, String>? headers,
}) => _client.get(url, headers: headers);

Future<package_http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _client.post(url, headers: _headers(headers), body: body, encoding: encoding);

Future<package_http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _client.put(url, headers: _headers(headers), body: body, encoding: encoding);

Future<package_http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _client.patch(url, headers: _headers(headers), body: body, encoding: encoding);

Future<package_http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _client.delete(url, headers: _headers(headers), body: body, encoding: encoding);

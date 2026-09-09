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

import 'dart:convert';
import 'package:http/http.dart' as http;

class EdgeApiException implements Exception {
  const EdgeApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class EdgeApiService {
  EdgeApiService({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final Uri baseUrl;
  final http.Client _client;
  Uri _uri(String path, [Map<String, String>? query]) =>
      baseUrl.resolve(path).replace(queryParameters: query);

  Future<Map<String, dynamic>> pair({
    String? adminKey,
    String? terminalKey,
    String? pairingCode,
  }) => _object(
    _client.post(
      _uri('/v1/pair'),
      headers: {
        'Content-Type': 'application/json',
        if (adminKey != null && adminKey.isNotEmpty) 'X-Lyncar-Edge-Key': adminKey,
      },
      body: jsonEncode({
        if (terminalKey != null && terminalKey.isNotEmpty) 'terminal_key': terminalKey,
        if (pairingCode != null && pairingCode.isNotEmpty) 'pairing_code': pairingCode.trim().toUpperCase(),
      }),
    ),
  );
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    int? terminalId,
  }) => _object(
    _client.post(
      _uri('/v1/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        ...terminalId == null ? const {} : {'terminal_id': terminalId},
      }),
    ),
  );
  Future<Map<String, dynamic>> session(String token) =>
      _object(_client.get(_uri('/v1/terminal/session'), headers: _auth(token)));
  Future<List<Map<String, dynamic>>> orders(String token) => _list(
    _client.get(_uri('/v1/orders', {'limit': '200'}), headers: _auth(token)),
  );
  Future<Map<String, dynamic>> catalog(String token) =>
      _object(_client.get(_uri('/v1/pedeon/catalog'), headers: _auth(token)));
  Future<Map<String, dynamic>> printers(String token) =>
      _object(_client.get(_uri('/v1/printers'), headers: _auth(token)));
  Future<Map<String, dynamic>> savePrinterBinding(
    String token,
    Map<String, dynamic> payload,
  ) => _object(
    _client.put(
      _uri('/v1/printers/bindings'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ),
  );
  Future<Map<String, dynamic>> testPrinter(
    String token, {
    required String printerName,
    required String logicalName,
  }) => _object(
    _client.post(
      _uri('/v1/printers/test'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'printer_name': printerName,
        'logical_name': logicalName,
      }),
    ),
  );
  Future<Map<String, dynamic>> createStaffOrder(
    String token,
    Map<String, dynamic> payload,
  ) => _object(
    _client.post(
      _uri('/v1/staff/orders'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ),
  );
  Future<void> transition(String token, String publicId, String status) async {
    await _object(
      _client.post(
        _uri('/v1/orders/$publicId/transition'),
        headers: {..._auth(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': status,
          'idempotency_key':
              'terminal:$publicId:$status:${DateTime.now().microsecondsSinceEpoch}',
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> checkout(
    String token,
    String publicId,
    Map<String, dynamic> payload,
  ) => _object(
    _client.post(
      _uri('/v1/orders/$publicId/checkout'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ),
  );

  Future<Map<String, dynamic>?> openCashSession(String token) async {
    final response = await _client.get(
      _uri('/v1/cash-sessions/open'),
      headers: _auth(token),
    );
    if (response.statusCode == 200 && response.body.trim() == 'null') {
      return null;
    }
    final decoded = _decode(response);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<Map<String, dynamic>> openCash(
    String token, {
    required int operatorId,
    required String operatorName,
    required String operatorType,
    required String register,
    required double openingAmount,
  }) => _object(
    _client.post(
      _uri('/v1/cash-sessions/open'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'operator_id': operatorId,
        'operator_name': operatorName,
        'operator_type': operatorType,
        'cash_register_number': register,
        'opening_amount': openingAmount,
      }),
    ),
  );

  Future<Map<String, dynamic>> closeCash(
    String token, {
    required String code,
    required String pin,
    required double countedCashAmount,
    String? notes,
  }) => _object(
    _client.post(
      _uri('/v1/cash-sessions/close'),
      headers: {..._auth(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'pin': pin,
        'counted_cash_amount': countedCashAmount,
        'notes': notes,
      }),
    ),
  );

  Future<List<Map<String, dynamic>>> syncIssues(String token) =>
      _list(_client.get(_uri('/v1/sync/issues'), headers: _auth(token)));

  Map<String, String> _auth(String token) => {'X-Lyncar-Edge-Token': token};

  Future<Map<String, dynamic>> _object(Future<http.Response> pending) async {
    final decoded = _decode(await pending);
    if (decoded is! Map<String, dynamic>) {
      throw const EdgeApiException('Resposta invalida do Lyncar Edge.');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> _list(
    Future<http.Response> pending,
  ) async {
    final decoded = _decode(await pending);
    if (decoded is! List<dynamic>) {
      throw const EdgeApiException('Lista invalida do Lyncar Edge.');
    }
    return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  dynamic _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw EdgeApiException(
        detail == null || '$detail'.trim().isEmpty
            ? 'Falha no Lyncar Edge.'
            : '$detail',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

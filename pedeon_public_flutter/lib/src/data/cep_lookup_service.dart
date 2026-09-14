import 'dart:convert';

import 'package:http/http.dart' as http;

/// Endereço retornado pelo ViaCEP para acelerar o preenchimento no checkout.
/// O cliente continua podendo ajustar todos os campos antes de enviar o pedido.
class CepAddress {
  const CepAddress({
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
  });

  final String street;
  final String neighborhood;
  final String city;
  final String state;

  factory CepAddress.fromJson(Map<String, Object?> json) => CepAddress(
    street: (json['logradouro'] as String? ?? '').trim(),
    neighborhood: (json['bairro'] as String? ?? '').trim(),
    city: (json['localidade'] as String? ?? '').trim(),
    state: (json['uf'] as String? ?? '').trim().toUpperCase(),
  );
}

class CepNotFoundException implements Exception {
  const CepNotFoundException();
}

class CepLookupService {
  const CepLookupService({this._client});

  final http.Client? _client;

  Future<CepAddress> lookup(String value) async {
    final cep = value.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      throw const FormatException('Informe os 8 dígitos do CEP.');
    }

    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Não foi possível consultar o CEP agora.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?> || decoded['erro'] == true) {
        throw const CepNotFoundException();
      }
      return CepAddress.fromJson(decoded);
    } finally {
      if (_client == null) client.close();
    }
  }
}

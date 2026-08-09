import 'dart:convert';

import 'package:http/http.dart' as http;

class CepAddress {
  const CepAddress({
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.cityCode,
  });

  final String street;
  final String neighborhood;
  final String city;
  final String state;
  final String? cityCode;
}

class CepService {
  const CepService();

  Future<CepAddress> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) {
      throw const CepLookupException('Informe um CEP com 8 digitos.');
    }
    final response = await http.get(
      Uri.parse('https://viacep.com.br/ws/$digits/json/'),
    );
    if (response.statusCode != 200) {
      throw const CepLookupException('Nao foi possivel consultar o CEP.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['erro'] == true) {
      throw const CepLookupException('CEP nao encontrado.');
    }
    return CepAddress(
      street: data['logradouro'] as String? ?? '',
      neighborhood: data['bairro'] as String? ?? '',
      city: data['localidade'] as String? ?? '',
      state: data['uf'] as String? ?? '',
      cityCode: data['ibge'] as String?,
    );
  }
}

class CepLookupException implements Exception {
  const CepLookupException(this.message);

  final String message;
}

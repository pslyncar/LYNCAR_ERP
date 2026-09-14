import 'dart:convert';

import 'package:http/http.dart' as http;

class CepAddress {
  const CepAddress({
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.cityCode,
    this.latitude,
    this.longitude,
  });

  final String street;
  final String neighborhood;
  final String city;
  final String state;
  final String? cityCode;
  final double? latitude;
  final double? longitude;
}

class CepService {
  const CepService();

  Future<CepAddress> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) {
      throw const CepLookupException('Informe um CEP com 8 digitos.');
    }
    final response = await http.get(
      Uri.parse('https://brasilapi.com.br/api/cep/v2/$digits'),
    );
    if (response.statusCode != 200) {
      throw const CepLookupException('Nao foi possivel consultar o CEP.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['errors'] != null) {
      throw const CepLookupException('CEP nao encontrado.');
    }
    final location = (data['location'] as Map?)?.cast<String, dynamic>();
    final coordinates = (location?['coordinates'] as Map?)
        ?.cast<String, dynamic>();
    return CepAddress(
      street: data['street'] as String? ?? '',
      neighborhood: data['neighborhood'] as String? ?? '',
      city: data['city'] as String? ?? '',
      state: data['state'] as String? ?? '',
      cityCode: (data['ibge'] as Map?)?['city']?.toString(),
      latitude: double.tryParse('${coordinates?['latitude'] ?? ''}'),
      longitude: double.tryParse('${coordinates?['longitude'] ?? ''}'),
    );
  }
}

class CepLookupException implements Exception {
  const CepLookupException(this.message);

  final String message;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_public/src/data/api_base_url.dart';

void main() {
  test('usa o IP da rede local em vez de localhost do celular', () {
    expect(
      resolvePedeOnApiBaseUrl(
        pageUri: Uri.parse('http://192.168.1.21:5001/drikapadaria'),
      ),
      'http://192.168.1.21:8000',
    );
  });

  test('preserva configuração explícita de implantação', () {
    expect(
      resolvePedeOnApiBaseUrl(
        configured: 'https://api.exemplo.com/',
        pageUri: Uri.parse('http://192.168.1.21:5001'),
      ),
      'https://api.exemplo.com',
    );
  });

  test('usa a API pública oficial fora da rede local', () {
    expect(
      resolvePedeOnApiBaseUrl(
        pageUri: Uri.parse('https://pedeon.lyncar.com.br/drikapadaria'),
      ),
      'https://api.lyncar.com.br',
    );
  });
}

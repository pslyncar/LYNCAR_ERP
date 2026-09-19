/// Resolve o endereço da API sem confundir o computador com o dispositivo que
/// abriu o cardápio.
///
/// Em produção, o PedeOn usa a API pública da Lyncar. Em desenvolvimento na
/// rede local, a API fica no mesmo host do cardápio, na porta 8000.
String resolvePedeOnApiBaseUrl({String? configured, Uri? pageUri}) {
  final override = (configured ?? '').trim();
  if (override.isNotEmpty) return _withoutTrailingSlash(override);

  final current = pageUri ?? Uri.base;
  final host = current.host;
  if (_isLocalHost(host)) {
    return Uri(scheme: current.scheme, host: host, port: 8000).toString();
  }

  return 'https://api.lyncar.com.br';
}

bool _isLocalHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  final parts = host.split('.').map(int.tryParse).toList(growable: false);
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

String _withoutTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

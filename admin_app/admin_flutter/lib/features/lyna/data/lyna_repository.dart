import '../../../models/session.dart';
import '../../../services/api_client.dart';
import '../domain/lyna_models.dart';

class LynaRepository {
  LynaRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<LynaReply> ask(
    Session session, {
    required String message,
    required String screen,
    required String module,
    required String conversation,
  }) => _apiClient.askLyna(
    session.token,
    message: message,
    screen: screen,
    module: module,
    context: {
      'empresa_nome': session.companyName,
      'plano': session.planCode,
      'conversa': conversation,
    },
  );
}

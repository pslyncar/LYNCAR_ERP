import 'package:flutter/foundation.dart';

import '../../../models/session.dart';
import '../data/lyna_repository.dart';

class LynaChatLine {
  const LynaChatLine({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class LynaViewModel extends ChangeNotifier {
  LynaViewModel({required this._repository});

  final LynaRepository _repository;
  final List<LynaChatLine> _lines = [
    const LynaChatLine(
      text:
          'Olá! Eu sou a Lyna. Posso explicar esta tela e ajudar a encontrar informações no Lyncar.',
      fromUser: false,
    ),
  ];

  List<LynaChatLine> get lines => List.unmodifiable(_lines);
  bool get busy => _busy;
  String? get error => _error;

  bool _busy = false;
  String? _error;

  Future<void> ask(
    Session session, {
    required String text,
    required String screen,
    required String module,
  }) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    _error = null;
    _lines.add(LynaChatLine(text: message, fromUser: true));
    _busy = true;
    notifyListeners();
    try {
      final reply = await _repository.ask(
        session,
        message: message,
        screen: screen,
        module: module,
        conversation: _conversationContext,
      );
      _lines.add(LynaChatLine(text: reply.message, fromUser: false));
    } catch (exception) {
      _error = exception.toString();
      _lines.add(
        const LynaChatLine(
          text:
              'Não consegui responder agora. Verifique a conexão local da Lyna e tente novamente.',
          fromUser: false,
        ),
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String get _conversationContext {
    final recent = _lines.length > 8
        ? _lines.sublist(_lines.length - 8)
        : _lines;
    return recent
        .map((line) => '${line.fromUser ? 'Usuário' : 'Lyna'}: ${line.text}')
        .join('\n');
  }
}

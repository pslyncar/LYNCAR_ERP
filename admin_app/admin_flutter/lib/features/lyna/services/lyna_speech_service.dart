import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Mantém voz e ditado atrás de uma camada pequena para podermos trocar o
/// reconhecimento nativo por um motor local no futuro sem alterar o chat.
class LynaSpeechService {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  bool _ttsReady = false;
  bool _speechInitialized = false;

  bool get isListening => _speech.isListening;

  Future<void> speak(String text) async {
    if (!_ttsReady) {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() => _tts.stop();

  Future<bool> startListening({
    required void Function(SpeechRecognitionResult result) onResult,
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async {
    if (!_speechInitialized) {
      _speechInitialized = await _speech.initialize(
        onStatus: onStatus,
        onError: (error) => onError(error.errorMsg),
      );
    }
    if (!_speechInitialized) return false;
    await _speech.listen(
      onResult: onResult,
      listenOptions: SpeechListenOptions(
        localeId: 'pt_BR',
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      ),
    );
    return true;
  }

  Future<void> stopListening() => _speech.stop();

  Future<void> cancelListening() => _speech.cancel();

  Future<void> dispose() async {
    await _tts.stop();
    await _speech.cancel();
  }
}

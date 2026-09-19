# Lyna: voz e acessibilidade

## Primeira versão

- `flutter_tts` lê uma resposta da Lyna somente quando a pessoa toca no botão de áudio.
- `speech_to_text` transforma a fala em texto no campo da pergunta.
- A transcrição é revisável: nada é enviado automaticamente para a Lyna.
- O áudio não é gravado pelo Lyncar nem salvo no banco.
- O idioma inicial é português do Brasil (`pt_BR`).

O reconhecimento usa o mecanismo disponível no aparelho ou navegador. Por isso o sistema pode pedir permissão de microfone e a disponibilidade pode variar entre navegadores/dispositivos. O reconhecimento nativo é adequado para perguntas curtas; um motor offline com Qwen3-ASR/sherpa-onnx fica reservado para uma etapa futura.

## Permissões

No Android foi adicionada a permissão de microfone e as consultas necessárias para reconhecimento de voz e síntese de fala. No navegador, o próprio navegador solicita a permissão quando o usuário toca no microfone.

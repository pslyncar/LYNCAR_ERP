import 'package:flutter/material.dart';

import '../../../models/session.dart';
import '../../../services/api_client.dart';
import '../data/lyna_repository.dart';
import 'lyna_view_model.dart';

class LynaChatOverlay extends StatefulWidget {
  const LynaChatOverlay({
    super.key,
    required this.session,
    required this.screen,
    required this.module,
  });

  final Session session;
  final String screen;
  final String module;

  @override
  State<LynaChatOverlay> createState() => _LynaChatOverlayState();
}

class _LynaChatOverlayState extends State<LynaChatOverlay> {
  late final LynaViewModel _viewModel;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _viewModel = LynaViewModel(
      repository: LynaRepository(
        apiClient: ApiClient(widget.session.apiBaseUrl),
      ),
    );
    _viewModel.addListener(_scrollToEnd);
  }

  @override
  void didUpdateWidget(covariant LynaChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.apiBaseUrl != widget.session.apiBaseUrl) {
      // The current conversation remains visible; a new repository is not
      // needed until the user logs into another session.
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_scrollToEnd);
    _viewModel.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _inputController.text;
    _inputController.clear();
    _viewModel.ask(
      widget.session,
      text: text,
      screen: widget.screen,
      module: widget.module,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    return Positioned(
      right: compact ? 14 : 24,
      bottom: compact ? 14 : 24,
      child: Material(
        color: Colors.transparent,
        child: _open
            ? _buildPanel(context, compact)
            : FloatingActionButton.extended(
                heroTag: 'lyna-open-chat',
                onPressed: () => setState(() => _open = true),
                icon: const _LynaAvatar(size: 28),
                label: const Text('Lyna'),
              ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, bool compact) {
    final width = compact ? MediaQuery.sizeOf(context).width - 28 : 380.0;
    return Container(
      width: width.clamp(280.0, 420.0),
      height: compact ? MediaQuery.sizeOf(context).height * .72 : 560,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 8, 13),
              color: const Color(0xFF0E1827),
              child: Row(
                children: [
                  const _LynaAvatar(size: 36),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lyna',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Inteligência integrada ao Lyncar',
                          style: TextStyle(
                            color: Color(0xFFB9C8D9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Recolher Lyna',
                    child: Material(
                      color: const Color(0xFF26364A),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _open = false),
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: const Color(0xFFF2F6FB),
              child: Text(
                'Tela atual: ${widget.screen}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF53657D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: _viewModel.lines.length,
                itemBuilder: (context, index) {
                  final line = _viewModel.lines[index];
                  return Align(
                    alignment: line.fromUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: line.fromUser
                            ? const Color(0xFF135A77)
                            : const Color(0xFFF2F6FB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        line.text,
                        style: TextStyle(
                          color: line.fromUser
                              ? Colors.white
                              : const Color(0xFF26364A),
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_viewModel.busy) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_viewModel.busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Pergunte sobre esta tela...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar pergunta',
                    onPressed: _viewModel.busy ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LynaAvatar extends StatelessWidget {
  const _LynaAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: ColoredBox(
        color: const Color(0xFFF7FAFF),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Image.asset(
            'assets/lyna/LYNA_SEM_FUNDO.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

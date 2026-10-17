import 'package:flutter/material.dart';

import '../../core/ai/ai_engine.dart';
import '../../core/ai/llama_native_engine.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <AiMessage>[];
  final _engine = LlamaNativeEngine.instance;
  bool _sending = false;
  bool _scrollScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _sending || !_engine.isModelLoaded) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    final prompt = [..._messages, AiMessage(role: 'user', text: question)];
    setState(() {
      _sending = true;
      _messages.add(AiMessage(role: 'user', text: question));
      _messages.add(const AiMessage(role: 'assistant', text: ''));
    });
    _toBottom();
    String response = '';
    try {
      await for (final part in _engine.streamReply(prompt)) {
        response += part;
        if (!mounted) break;
        setState(() {
          _messages[_messages.length - 1] = AiMessage(role: 'assistant', text: response);
        });
        _toBottom();
      }
      if (mounted && response.isEmpty) {
        setState(() => _messages[_messages.length - 1] = const AiMessage(
          role: 'assistant', text: 'Модель завершила генерацию без текста. Попробуй ещё раз.',
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages[_messages.length - 1] = AiMessage(
          role: 'assistant', text: 'Ошибка: $e',
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _engine,
      builder: (context, _) => Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Icon(_engine.isModelLoaded ? Icons.circle : Icons.circle_outlined,
                    size: 11, color: _engine.isModelLoaded ? Colors.lightGreenAccent : Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(_engine.isModelLoaded
                    ? _engine.status
                    : 'Модель не запущена — открой «Модели»',
                    style: Theme.of(context).textTheme.bodySmall)),
                IconButton(
                  tooltip: 'Новый диалог',
                  onPressed: _sending || _messages.isEmpty ? null : () {
                    setState(_messages.clear);
                  },
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ]),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.psychology_outlined, size: 64),
                      const SizedBox(height: 16),
                      Text('Мой локальный ИИ', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('Добавь GGUF в разделе «Модели», запусти Qwen и напиши вопрос.', textAlign: TextAlign.center),
                    ]),
                  ))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final user = m.role == 'user';
                      return Align(
                        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                          child: Card(
                            color: user ? Theme.of(context).colorScheme.primaryContainer : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(m.text.isEmpty ? '● ● ●' : m.text),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_sending && _engine.isModelLoaded,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Напиши сообщение…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                )),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: _sending ? 'Остановить' : 'Отправить',
                  icon: Icon(_sending ? Icons.stop_rounded : Icons.send_rounded),
                  onPressed: _sending ? _engine.stop : (_engine.isModelLoaded ? _send : null),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

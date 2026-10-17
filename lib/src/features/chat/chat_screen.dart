import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_engine.dart';
import '../../core/ai/llama_native_engine.dart';
import '../../core/memory/conversation_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _engine = LlamaNativeEngine.instance;
  final _repository = LocalConversationRepository.instance;

  List<AiMessage> _messages = [];
  List<ChatThread> _threads = [];
  List<MemoryNote> _memory = [];
  String? _activeId;
  bool _ready = false;
  String? _loadError;
  bool _sending = false;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final threads = List<ChatThread>.of(await _repository.loadConversations());
      final memory = List<MemoryNote>.of(await _repository.loadMemory());
      if (!mounted) return;
      threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _threads = threads;
        _memory = memory;
        if (threads.isNotEmpty) {
          _activeId = threads.first.id;
          _messages = List.of(threads.first.messages);
          if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _messages.last.text.isEmpty) {
            _messages.removeLast();
          }
        }
        _ready = true;
      });
      _toBottom();
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

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
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _makeId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _suggestTitle(String text) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final characters = singleLine.runes.toList();
    return String.fromCharCodes(characters.take(45)) +
        (characters.length > 45 ? '…' : '');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _writeThreads() async {
    try {
      await _repository.saveConversations(List.of(_threads));
    } catch (e) {
      _showError('Не удалось сохранить диалоги: $e');
    }
  }

  Future<void> _writeMemory() async {
    try {
      await _repository.saveMemory(List.of(_memory));
    } catch (e) {
      _showError('Не удалось сохранить память: $e');
    }
  }

  void _saveActive() {
    if (!_ready || _activeId == null) return;
    final now = DateTime.now();
    final index = _threads.indexWhere((chat) => chat.id == _activeId);
    if (index < 0) {
      final firstQuestion = _messages.firstWhere(
        (m) => m.role == 'user',
        orElse: () => const AiMessage(role: 'user', text: 'Новый диалог'),
      );
      _threads.add(ChatThread(
        id: _activeId!,
        title: _suggestTitle(firstQuestion.text),
        createdAt: now,
        updatedAt: now,
        messages: List.unmodifiable(_messages),
      ));
    } else {
      _threads[index] = _threads[index].copyWith(
        updatedAt: now,
        messages: List.unmodifiable(_messages),
      );
    }
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    unawaited(_writeThreads());
  }

  void _newChat() {
    if (_sending || !_ready) return;
    setState(() {
      _activeId = null;
      _messages = [];
      _controller.clear();
    });
  }

  void _openChat(ChatThread chat) {
    if (_sending) return;
    setState(() {
      _activeId = chat.id;
      _messages = List.of(chat.messages);
      if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _messages.last.text.isEmpty) {
        _messages.removeLast();
      }
      _controller.clear();
    });
    _toBottom();
  }

  Future<void> _rename(ChatThread chat) async {
    final editor = TextEditingController(text: chat.title);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать диалог'),
        content: TextField(
          autofocus: true,
          controller: editor,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || value == null || value.isEmpty) return;
    setState(() {
      final index = _threads.indexWhere((e) => e.id == chat.id);
      if (index >= 0) _threads[index] = _threads[index].copyWith(title: value);
    });
    unawaited(_writeThreads());
  }

  Future<void> _delete(ChatThread chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить диалог?'),
        content: Text('«${chat.title}» будет удалён из истории на этом телефоне.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _threads.removeWhere((e) => e.id == chat.id);
      if (_activeId == chat.id) {
        if (_threads.isEmpty) {
          _activeId = null;
          _messages = [];
        } else {
          _activeId = _threads.first.id;
          _messages = List.of(_threads.first.messages);
          if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _messages.last.text.isEmpty) {
            _messages.removeLast();
          }
        }
      }
    });
    unawaited(_writeThreads());
  }

  Future<void> _showHistory() async {
    if (_sending || !_ready) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 10, 10),
              child: Row(children: [
                const Expanded(child: Text('История диалогов', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Новый чат',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () { Navigator.pop(sheetContext); _newChat(); },
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: _threads.isEmpty
              ? const Center(child: Text('Здесь появятся сохранённые переписки'))
              : ListView.builder(
                  itemCount: _threads.length,
                  itemBuilder: (context, index) {
                    final chat = _threads[index];
                    return ListTile(
                      selected: chat.id == _activeId,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${chat.messages.length} сообщений · ${_date(chat.updatedAt)}'),
                      onTap: () { Navigator.pop(sheetContext); _openChat(chat); },
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Действия с диалогом',
                        onSelected: (action) {
                          Navigator.pop(sheetContext);
                          if (action == 'rename') unawaited(_rename(chat));
                          if (action == 'delete') unawaited(_delete(chat));
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                          PopupMenuItem(value: 'delete', child: Text('Удалить')),
                        ],
                      ),
                    );
                  },
                )),
          ]),
        ),
      ),
    );
  }

  String _date(DateTime date) {
    final d = date.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }

  Future<void> _editNote({MemoryNote? note, String initialText = ''}) async {
    if (_sending || !_ready) return;
    final editor = TextEditingController(text: note?.text ?? initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(note == null ? 'Запомнить' : 'Изменить заметку'),
        content: TextField(
          controller: editor,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'Факт или инструкция, которую нужно помнить между чатами',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    setState(() {
      if (note == null) {
        _memory.add(MemoryNote(id: _makeId(), text: text));
      } else {
        final index = _memory.indexWhere((e) => e.id == note.id);
        if (index >= 0) _memory[index] = MemoryNote(id: note.id, text: text);
      }
    });
    unawaited(_writeMemory());
  }

  Future<void> _removeNote(MemoryNote note) async {
    if (_sending) return;
    setState(() => _memory.removeWhere((e) => e.id == note.id));
    unawaited(_writeMemory());
  }

  Future<void> _showMemory() async {
    if (_sending || !_ready) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 10, 8),
              child: Row(children: [
                const Expanded(child: Text('Память ИИ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Добавить заметку',
                  icon: const Icon(Icons.add),
                  onPressed: () { Navigator.pop(sheetContext); unawaited(_editNote()); },
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Заметки сохраняются только на телефоне и доступны в новых чатах. В запрос передаётся ограниченное количество заметок.'),
            ),
            const Divider(height: 1),
            Expanded(child: _memory.isEmpty
              ? const Center(child: Text('Пока ничего не сохранено'))
              : ListView.builder(
                  itemCount: _memory.length,
                  itemBuilder: (_, index) {
                    final note = _memory[index];
                    return ListTile(
                      title: Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                      onTap: () { Navigator.pop(sheetContext); unawaited(_editNote(note: note)); },
                      trailing: IconButton(
                        tooltip: 'Удалить заметку',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () { Navigator.pop(sheetContext); unawaited(_removeNote(note)); },
                      ),
                    );
                  },
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || !_ready || _sending || !_engine.isModelLoaded) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    final previous = List<AiMessage>.of(_messages);
    final recent = previous.length > 48 ? previous.sublist(previous.length - 48) : previous;
    final prompt = buildConversationPrompt(
      [...recent, AiMessage(role: 'user', text: question)], _memory,
    );
    final targetIndex = _messages.length + 1;
    setState(() {
      _activeId ??= _makeId();
      _sending = true;
      _messages.add(AiMessage(role: 'user', text: question));
      _messages.add(const AiMessage(role: 'assistant', text: ''));
    });
    _saveActive();
    _toBottom();

    String response = '';
    try {
      await for (final part in _engine.streamReply(prompt)) {
        response += part;
        if (!mounted) break;
        setState(() => _messages[targetIndex] = AiMessage(role: 'assistant', text: response));
        _toBottom();
      }
      if (mounted && response.isEmpty) {
        setState(() => _messages[targetIndex] = const AiMessage(
          role: 'assistant', text: 'Модель не вернула текст. Попробуй ещё раз.',
        ));
      }
    } catch (e) {
      if (mounted) {
        if (response.isEmpty) {
          // An error is not a model response: keep it out of subsequent prompts.
          setState(() => _messages.removeAt(targetIndex));
        } else {
          setState(() => _messages[targetIndex] = AiMessage(role: 'assistant', text: response));
        }
        _showError('Ошибка ответа: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _saveActive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          const Text('Не удалось прочитать сохранённые диалоги.'),
          const SizedBox(height: 8),
          Text(_loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => setState(() { _loadError = null; unawaited(_initialize()); }), child: const Text('Повторить')),
        ]),
      ));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());

    return AnimatedBuilder(
      animation: _engine,
      builder: (context, _) => Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(children: [
              IconButton(
                tooltip: 'История чатов',
                icon: const Icon(Icons.history),
                onPressed: _sending ? null : _showHistory,
              ),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_activeId == null ? 'Новый диалог' : _threads.firstWhere(
                    (t) => t.id == _activeId,
                    orElse: () => ChatThread(id: '', title: 'Диалог', createdAt: DateTime.now(), updatedAt: DateTime.now(), messages: const []),
                  ).title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_engine.isModelLoaded ? _engine.status : 'Модель не запущена — открой «Модели»',
                    style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              )),
              IconButton(
                tooltip: 'Память ИИ',
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: _sending ? null : _showMemory,
              ),
              IconButton(
                tooltip: 'Новый диалог',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: _sending ? null : _newChat,
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
                    const Text('Напиши вопрос. Чаты сохраняются на телефоне, даже после закрытия приложения.', textAlign: TextAlign.center),
                  ]),
                ))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                        child: GestureDetector(
                          onLongPress: _sending || message.text.isEmpty ? null : () => _editNote(initialText: message.text.length > 300 ? message.text.substring(0, 300) : message.text),
                          child: Card(
                            color: isUser ? Theme.of(context).colorScheme.primaryContainer : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(message.text.isEmpty ? '● ● ●' : message.text),
                            ),
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
      ]),
    );
  }
}

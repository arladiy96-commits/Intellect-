import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_engine.dart';
import '../../core/ai/llama_native_engine.dart';
import '../../core/baboon/baboon_core.dart';
import '../../core/memory/conversation_repository.dart';
import '../../core/memory/shared_memory_store.dart';
import '../memory/memory_screen.dart';
import '../knowledge/knowledge_editor_screen.dart';
import '../tools/photo_preview_screen.dart';
import '../../ui/baboon_style.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _engine = LlamaNativeEngine.instance;
  final _core = BaboonCore.instance;
  final _repository = LocalConversationRepository.instance;
  final _memoryStore = SharedMemoryStore.instance;

  List<AiMessage> _messages = [];
  List<ChatThread> _threads = [];
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
      await _memoryStore.ensureLoaded();
      if (!mounted) return;
      threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _threads = threads;
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

  Future<void> _editNote({String initialText = ''}) async {
    if (_sending || !_ready) return;
    final editor = TextEditingController(text: initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить в память'),
        content: TextField(
          controller: editor,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'Что Бабуин должен помнить во всех чатах?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    try {
      await _memoryStore.save(text: text,
        category: suggestMemoryCategory(text));
      _showError('Сохранено в общей памяти Бабуина');
    } catch (e) {
      _showError('Не удалось сохранить память: $e');
    }
  }

  Future<void> _showMemory() async {
    if (_sending || !_ready) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MemoryScreen()),
    );
  }

  void _attachments() {
    if (_sending) return;
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      backgroundColor: BaboonColors.surface,
      builder: (sheetContext) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.note_add_outlined),
            title: const Text('Добавить знание'),
            subtitle: const Text('Текст или файл TXT/MD'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => const KnowledgeEditorScreen()));
            }),
          ListTile(leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Анализ фото'),
            subtitle: const Text('Макет · OCR подключим позже'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => const PhotoPreviewScreen()));
            }),
          ListTile(leading: const Icon(Icons.attach_file_outlined),
            title: const Text('Файл к сообщению'),
            subtitle: const Text('Подключим в следующем этапе'),
            onTap: () {
              Navigator.pop(sheetContext);
              baboonSoon(context, 'Вложения',
                'Добавление файла прямо в запрос подключим позже. '
                'TXT/MD можно уже сохранять в базе знаний.');
            }),
        ])),
      );
  }

  void _followUp(String value) {
    if (_sending || !_ready) return;
    _controller.text = value;
    if (_engine.isModelLoaded) {
      unawaited(_send());
    } else {
      _showError('Для нового объяснения включи облачную или локальную модель.');
    }
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || !_ready || _sending) return;
    if (!_engine.isModelLoaded && !_core.canHandle(question)) {
      _showError('Для этого вопроса сначала запусти ИИ. Простые вычисления и поиск по базе доступны без модели.');
      return;
    }
    _controller.clear();
    FocusScope.of(context).unfocus();
    // Persist explicit "Запомни, что..." commands before composing the prompt.
    // All chats share a single in-memory store backed by memory.v1.json.
    setState(() => _sending = true);
    try {
      await _memoryStore.captureExplicit(question);
    } catch (e) {
      _showError('Не удалось сохранить воспоминание: $e');
    }
    if (!mounted) return;
    final previous = List<AiMessage>.of(_messages);
    final safePrevious = _engine.cloudEnabled
        ? _core.cloudSafeHistory(previous)
        : previous;
    final recent = safePrevious.length > 48
        ? safePrevious.sublist(safePrevious.length - 48) : safePrevious;
    final prompt = buildConversationPrompt(
      [...recent, AiMessage(role: 'user', text: question)], _memoryStore.notes,
    );
    final targetIndex = _messages.length + 1;
    setState(() {
      _activeId ??= _makeId();
      _messages.add(AiMessage(role: 'user', text: question));
      _messages.add(const AiMessage(role: 'assistant', text: ''));
    });
    _saveActive();
    _toBottom();

    String response = '';
    final paintClock = Stopwatch()..start();
    try {
      // Baboon Core executes safe, registered tools before consulting the
      // selected AI model. No knowledge documents leave the phone here.
      final tool = await _core.tryTool(question);
      if (tool != null) {
        response = tool.message;
      } else {
        await for (final part in _engine.streamReply(prompt)) {
          response += part;
          if (!mounted) break;
          // Groq may stream hundreds of chunks per second. Repaint no more
          // often than about 20 times/s, without dropping any text.
          if (paintClock.elapsedMilliseconds < 50) continue;
          paintClock.reset();
          setState(() => _messages[targetIndex] = AiMessage(role: 'assistant', text: response));
          _toBottom();
        }
      }
      if (mounted) {
        setState(() => _messages[targetIndex] = AiMessage(
          role: 'assistant', text: response.isEmpty
              ? 'Модель не вернула текст. Попробуй ещё раз.' : response,
        ));
        _toBottom();
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
          color: BaboonColors.background,
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
                  Text(_engine.isModelLoaded ? _engine.status : 'Без модели доступны математические инструменты и поиск по знаниям',
                    style: const TextStyle(fontSize: 11, color: BaboonColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
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
        if (_engine.cloudEnabled &&
            (_engine.cloudLastUsage != null || _engine.cloudGroqQuota != null))
          Container(
            width: double.infinity,
            color: BaboonColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Text(
              [
                if (_engine.cloudLastUsage != null)
                  'Токены: ${_engine.cloudLastUsage!.promptTokens} вход / '
                  '${_engine.cloudLastUsage!.completionTokens} выход '
                  '(всего ${_engine.cloudLastUsage!.totalTokens})',
                if (_engine.cloudProviderTitle == 'Groq' &&
                    _engine.cloudGroqQuota?.minuteTokensRemaining != null)
                  'Доступно: ${_engine.cloudGroqQuota!.minuteTokensRemaining} т/мин',
              ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.psychology_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text('Бабуин — локальный и облачный ИИ', style: Theme.of(context).textTheme.titleLarge),
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
                    final lastAssistant = index == _messages.length - 1 && !isUser &&
                        message.text.isNotEmpty && !_sending;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Column(crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                        if (!isUser) const Padding(
                          padding: EdgeInsets.only(left: 5, bottom: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            BaboonAvatar(radius: 11), SizedBox(width: 6),
                            Text('Бабуин', style: TextStyle(
                              fontSize: 11, color: BaboonColors.gold)),
                          ])),
                        Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                            child: GestureDetector(
                              onLongPress: _sending || message.text.isEmpty ? null : () =>
                                _editNote(initialText: message.text.length > 300
                                  ? message.text.substring(0, 300) : message.text),
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: isUser ? BaboonColors.blue : BaboonColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isUser
                                    ? BaboonColors.blue : BaboonColors.border),
                                ),
                                child: SelectableText(message.text.isEmpty ? '● ● ●' : message.text,
                                  style: const TextStyle(fontSize: 14.5, height: 1.5)),
                              ),
                            ),
                          )),
                        if (lastAssistant) Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Wrap(spacing: 6, runSpacing: 2, children: [
                            ActionChip(label: const Text('Объясни проще'),
                              onPressed: () => _followUp('Объясни последнее решение проще и по шагам')),
                            ActionChip(label: const Text('Другой пример'),
                              onPressed: () => _followUp('Приведи похожий пример с решением')),
                            ActionChip(label: const Text('Похожее задание'),
                              onPressed: () => _followUp('Придумай похожее задание для тренировки')),
                          ])),
                      ]),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.add, color: BaboonColors.gold),
                tooltip: 'Вложения и файлы', onPressed: _sending ? null : _attachments),
              Expanded(child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                enabled: _ready && !_sending,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Напиши сообщение…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              )),
              IconButton(icon: const Icon(Icons.mic_none_outlined, size: 20),
                tooltip: 'Голосовой ввод', onPressed: () => baboonSoon(context,
                  'Голос', 'Голосовой ввод будет добавлен позже.')),
              const SizedBox(width: 4),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF91B8F9),
                  foregroundColor: const Color(0xFF082145)),
                tooltip: _sending ? 'Остановить' : 'Отправить',
                icon: Icon(_sending ? Icons.stop_rounded : Icons.send_rounded),
                onPressed: _sending ? _engine.stop : (_ready ? _send : null),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

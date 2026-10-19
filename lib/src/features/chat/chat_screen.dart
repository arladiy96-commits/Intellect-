import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ai/ai_engine.dart';
import '../../core/ai/llama_native_engine.dart';
import '../../core/chat/chat_session_controller.dart';
import '../../core/memory/conversation_repository.dart';
import '../../core/memory/shared_memory_store.dart';
import '../../ui/baboon_style.dart';
import '../knowledge/knowledge_editor_screen.dart';
import '../memory/memory_screen.dart';
import '../tools/photo_preview_screen.dart';

/// Pure chat UI: inference, persistence and queue live in ChatSessionController.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _engine = LlamaNativeEngine.instance;
  final _session = ChatSessionController.instance;
  final _memory = SharedMemoryStore.instance;
  bool _stickToBottom = true;
  bool _scrollScheduled = false;
  String? _previousError;
  String? _displayedThreadId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _session.addListener(_onSessionUpdate);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _session.ensureLoaded();
      if (!mounted) return;
      _displayedThreadId = _session.activeId;
      _input.text = _session.draft;
      setState(() {});
      _toBottom(force: true);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionUpdate);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final close = _scroll.position.extentAfter < 110;
    if (close != _stickToBottom) setState(() => _stickToBottom = close);
  }

  void _onSessionUpdate() {
    if (!mounted) return;
    if (_displayedThreadId != _session.activeId) {
      _displayedThreadId = _session.activeId;
      _input.text = _session.draft;
      _toBottom(force: true);
    }
    final error = _session.error;
    if (error != null && error != _previousError && _session.ready) {
      _previousError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast(error);
      });
    }
    if (_stickToBottom) _toBottom();
  }

  void _toBottom({bool force = false}) {
    if (force) _stickToBottom = true;
    if ((!_stickToBottom && !force) || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients || !_stickToBottom) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _switchChat(String? id) {
    if (id == null) {
      _session.newChat();
    } else {
      _session.openChat(id);
    }
    _input.text = _session.draft;
    _toBottom(force: true);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _session.setDraft('');
    FocusScope.of(context).unfocus();
    try {
      await _session.send(text);
      _toBottom(force: true);
    } catch (e) {
      if (!mounted) return;
      _input.text = text;
      _session.setDraft(text);
      _toast('Не удалось отправить: $e');
    }
  }

  Future<void> _rename(ChatThread chat) async {
    final editor = TextEditingController(text: chat.title);
    final text = await showDialog<String>(
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
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            child: const Text('Сохранить')),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    try {
      await _session.rename(chat.id, text);
    } catch (e) {
      _toast('Переименование не сохранилось: $e');
    }
  }

  Future<void> _delete(ChatThread chat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить диалог?'),
        content: Text('«${chat.title}» будет удалён с телефона.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить')),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    try {
      await _session.delete(chat.id);
      _input.text = _session.draft;
      _toBottom(force: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _showHistory() async {
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
                const Expanded(child: Text('История диалогов',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Новый чат',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _switchChat(null);
                  },
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: _session.threads.isEmpty
                ? const Center(child: Text('Здесь появятся сохранённые переписки'))
                : ListView.builder(
                    itemCount: _session.threads.length,
                    itemBuilder: (context, index) {
                      final chat = _session.threads[index];
                      return ListTile(
                        selected: chat.id == _session.activeId,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(chat.title, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                        subtitle: Text('${chat.messages.length} сообщений · '
                          '${_date(chat.updatedAt)}'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _switchChat(chat.id);
                        },
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
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _editNote({String initialText = ''}) async {
    final editor = TextEditingController(text: initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить в память'),
        content: TextField(
          controller: editor, autofocus: true,
          minLines: 2, maxLines: 5, maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'Что Бабуин должен помнить во всех чатах?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            child: const Text('Сохранить')),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    try {
      await _memory.save(text: text, category: suggestMemoryCategory(text));
      _toast('Сохранено в общей памяти Бабуина');
    } catch (e) {
      _toast('Не удалось сохранить память: $e');
    }
  }

  Future<void> _showMemory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MemoryScreen()));
  }

  void _attachments() {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      backgroundColor: BaboonColors.surface,
      builder: (sheetContext) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            subtitle: const Text('Подключим на следующем этапе'),
            onTap: () {
              Navigator.pop(sheetContext);
              baboonSoon(context, 'Вложения',
                'TXT/MD пока можно сохранять в базе знаний.');
            }),
        ],
      )),
    );
  }

  void _followUp(String value) {
    _input.text = value;
    _session.setDraft(value);
    unawaited(_send());
  }

  Widget _message(AiMessage message, int index, List<AiMessage> messages) {
    final isUser = message.role == 'user';
    final waiting = message.status == 'queued';
    final running = message.status == 'generating';
    final failed = message.status == 'failed';
    final interrupted = message.status == 'interrupted';
    final lastAssistant = !isUser && index == messages.length - 1 &&
        message.status == 'completed' && message.text.isNotEmpty;
    final empty = message.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isUser
          ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser) const Padding(
            padding: EdgeInsets.only(left: 5, bottom: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              BaboonAvatar(radius: 11), SizedBox(width: 6),
              Text('Бабуин', style: TextStyle(fontSize: 11, color: BaboonColors.gold)),
            ]),
          ),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .88),
              child: GestureDetector(
                onLongPress: empty ? null : () => _editNote(
                  initialText: message.text.length > 300
                    ? message.text.substring(0, 300) : message.text),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: isUser ? BaboonColors.blue : BaboonColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isUser
                      ? BaboonColors.blue : BaboonColors.border),
                  ),
                  child: SelectableText(
                    empty ? (waiting ? 'В очереди…' : running
                      ? '● ● ●' : 'Ответ не получен') : message.text,
                    style: const TextStyle(fontSize: 14.5, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
          if (!isUser) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (waiting) const Text('В очереди', style: TextStyle(
                  fontSize: 11, color: BaboonColors.muted)),
                if (running) const Text('Отвечает…', style: TextStyle(
                  fontSize: 11, color: BaboonColors.muted)),
                if (interrupted) const Text('Ответ прерван', style: TextStyle(
                  fontSize: 11, color: BaboonColors.gold)),
                if (failed) const Text('Ошибка ответа', style: TextStyle(
                  fontSize: 11, color: BaboonColors.gold)),
                if (message.modelId != null) Text(message.modelId!,
                  style: const TextStyle(fontSize: 10, color: BaboonColors.muted)),
                if (!empty) IconButton(
                  tooltip: 'Копировать ответ',
                  icon: const Icon(Icons.copy_outlined, size: 17),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    _toast('Ответ скопирован');
                  },
                  visualDensity: VisualDensity.compact,
                ),
                if (failed || interrupted) TextButton.icon(
                  onPressed: () async {
                    try { await _session.retry(message.id!); }
                    catch (e) { _toast('Не удалось повторить: $e'); }
                  },
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
          if (lastAssistant) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              ActionChip(label: const Text('Объясни проще'),
                onPressed: () => _followUp('Объясни последнее решение проще и по шагам')),
              ActionChip(label: const Text('Другой пример'),
                onPressed: () => _followUp('Приведи похожий пример с решением')),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_engine, _session]),
      builder: (context, _) {
        if (_session.error != null && !_session.ready) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Не удалось прочитать сохранённые диалоги.'),
              const SizedBox(height: 8),
              Text(_session.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => unawaited(_initialize()),
                child: const Text('Повторить')),
            ]),
          ));
        }
        if (!_session.ready) return const Center(child: CircularProgressIndicator());
        final messages = _session.messages;
        return Column(children: [
          Material(
            color: BaboonColors.background,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(children: [
                IconButton(tooltip: 'История чатов', icon: const Icon(Icons.history),
                  onPressed: _showHistory),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_session.activeThread?.title ?? 'Новый диалог',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(_engine.isModelLoaded ? _engine.status
                        : 'Без модели доступны математические инструменты и поиск по знаниям',
                      style: const TextStyle(fontSize: 11, color: BaboonColors.muted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
                if (_session.queuedCount > 0) Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Очередь: ${_session.queuedCount}',
                    style: const TextStyle(fontSize: 11, color: BaboonColors.gold)),
                ),
                IconButton(tooltip: 'Память ИИ',
                  icon: const Icon(Icons.bookmarks_outlined),
                  onPressed: _showMemory),
                IconButton(tooltip: 'Новый диалог',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () => _switchChat(null)),
              ]),
            ),
          ),
          if (_engine.cloudEnabled &&
              (_engine.cloudLastUsage != null || _engine.cloudGroqQuota != null))
            Container(
              width: double.infinity,
              color: BaboonColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Text([
                if (_engine.cloudLastUsage != null)
                  'Токены: ${_engine.cloudLastUsage!.promptTokens} вход / '
                  '${_engine.cloudLastUsage!.completionTokens} выход '
                  '(всего ${_engine.cloudLastUsage!.totalTokens})',
                if (_engine.cloudProviderTitle == 'Groq' &&
                    _engine.cloudGroqQuota?.minuteTokensRemaining != null)
                  'Доступно: ${_engine.cloudGroqQuota!.minuteTokensRemaining} т/мин',
              ].join('  ·  '), maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(child: Stack(children: [
            messages.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.psychology_outlined, size: 64),
                      const SizedBox(height: 16),
                      Text('Бабуин — локальный и облачный ИИ',
                        style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('Напиши вопрос. Переписки и очередь сохраняются '
                        'на телефоне.', textAlign: TextAlign.center),
                    ]),
                  ))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _message(
                      messages[index], index, messages),
                  ),
            if (!_stickToBottom) Positioned(
              right: 12, bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'chat-scroll-bottom',
                tooltip: 'К последнему сообщению',
                onPressed: () => _toBottom(force: true),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
          ])),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.add, color: BaboonColors.gold),
                tooltip: 'Вложения и файлы', onPressed: _attachments),
              Expanded(child: TextField(
                controller: _input, minLines: 1, maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Напиши сообщение…', border: OutlineInputBorder()),
                onChanged: _session.setDraft,
                onSubmitted: (_) => unawaited(_send()),
              )),
              if (_session.isGenerating) IconButton(
                tooltip: 'Остановить генерацию',
                icon: const Icon(Icons.stop_circle_outlined, color: BaboonColors.gold),
                onPressed: () => unawaited(_session.stop()),
              ),
              IconButton(icon: const Icon(Icons.mic_none_outlined, size: 20),
                tooltip: 'Голосовой ввод', onPressed: () => baboonSoon(context,
                  'Голос', 'Голосовой ввод будет добавлен позже.')),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF91B8F9),
                  foregroundColor: const Color(0xFF082145)),
                tooltip: 'Отправить в очередь',
                icon: const Icon(Icons.send_rounded),
                onPressed: _send,
              ),
            ]),
          )),
        ]);
      },
    );
  }
}

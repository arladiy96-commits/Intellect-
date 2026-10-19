import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../ai/ai_engine.dart';
import '../ai/llama_native_engine.dart';
import '../baboon/baboon_core.dart';
import '../memory/conversation_repository.dart';
import '../memory/shared_memory_store.dart';

/// Adapter boundary: tests and future providers do not need an Android bridge.
abstract interface class ChatReplyGateway {
  bool get available;
  bool get cloudMode;
  String get modelId;
  Stream<String> reply(List<AiMessage> prompt);
  Future<void> stop();
}

abstract interface class ChatMemoryGateway {
  List<MemoryNote> get notes;
  Future<void> ensureLoaded();
  Future<void> captureExplicit(String message);
}

class NativeChatMemoryGateway implements ChatMemoryGateway {
  const NativeChatMemoryGateway(this.store);
  final SharedMemoryStore store;
  @override
  List<MemoryNote> get notes => store.notes;
  @override
  Future<void> ensureLoaded() => store.ensureLoaded();
  @override
  Future<void> captureExplicit(String message) async {
    await store.captureExplicit(message);
  }
}

class NativeChatReplyGateway implements ChatReplyGateway {
  const NativeChatReplyGateway(this.engine);
  final LlamaNativeEngine engine;

  @override
  bool get available => engine.isModelLoaded;
  @override
  bool get cloudMode => engine.cloudEnabled;
  @override
  String get modelId => engine.cloudEnabled
      ? '${engine.cloudProviderTitle}/${engine.cloudModel}'
      : 'local/${engine.activeModelPath?.split('/').last ?? 'qwen'}';
  @override
  Stream<String> reply(List<AiMessage> prompt) => engine.streamReply(prompt);
  @override
  Future<void> stop() => engine.stop();
}

class _PendingReply {
  _PendingReply(this.threadId, this.assistantId, this.userId,
      {this.prepared = false});
  final String threadId;
  final String assistantId;
  final String userId;
  // New turns cannot execute until persistence and explicit memory capture
  // complete. Prevents rapid concurrent sends from overtaking each other.
  bool prepared;
}

/// Application-scoped chat orchestration. It owns the single inference queue,
/// persists before requesting inference, and survives screen navigation.
/// Android process death interrupts an in-flight reply but keeps queued turns.
class ChatSessionController extends ChangeNotifier {
  ChatSessionController({
    required ConversationRepository repository,
    required ChatReplyGateway gateway,
    required BaboonCore core,
    required ChatMemoryGateway memory,
  }) : _repository = repository, _gateway = gateway,
       _core = core, _memory = memory;

  static final ChatSessionController instance = ChatSessionController(
    repository: LocalConversationRepository.instance,
    gateway: NativeChatReplyGateway(LlamaNativeEngine.instance),
    core: BaboonCore.instance,
    memory: NativeChatMemoryGateway(SharedMemoryStore.instance),
  ).._attachEngine();

  final ConversationRepository _repository;
  final ChatReplyGateway _gateway;
  final BaboonCore _core;
  final ChatMemoryGateway _memory;
  final List<ChatThread> _threads = [];
  final Queue<_PendingReply> _pending = Queue<_PendingReply>();
  final Map<String, String> _drafts = {};
  final Map<String, Timer> _draftTimers = {};
  Future<void>? _loading;
  Timer? _partialSaveTimer;
  bool _running = false;
  bool _cancelRequested = false;
  _PendingReply? _current;
  String? _activeId;
  String? error;
  bool ready = false;
  int _serialId = 0;

  List<ChatThread> get threads => List.unmodifiable(_threads);
  String? get activeId => _activeId;
  ChatThread? get activeThread => threadById(_activeId);
  List<AiMessage> get messages => activeThread?.messages ?? const [];
  bool get isGenerating => _current != null;
  int get queuedCount => _pending.length;
  bool get hasWork => _running || _pending.isNotEmpty;
  String get draft => _drafts[_activeId ?? '__new__'] ?? '';
  bool get canReply => _gateway.available;

  ChatThread? threadById(String? id) {
    if (id == null) return null;
    for (final t in _threads) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _attachEngine() {
    LlamaNativeEngine.instance.addListener(_resumeWhenReady);
  }

  void _resumeWhenReady() {
    if (_gateway.available && _pending.isNotEmpty) unawaited(_drain());
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final threads = await _repository.loadConversations();
      final drafts = await _repository.loadDrafts();
      await _memory.ensureLoaded();
      _threads..clear()..addAll(threads);
      _drafts..clear()..addAll(drafts);
      _sort();
      _activeId = _threads.isEmpty ? null : _threads.first.id;
      final restoredJobs = <(DateTime, _PendingReply)>[];
      for (final thread in List<ChatThread>.of(_threads)) {
        var repaired = false;
        final messages = thread.messages.map((m) {
          if (m.status == 'generating') {
            repaired = true;
            return m.copyWith(status: 'interrupted');
          }
          return m;
        }).toList();
        if (repaired) {
          _replace(thread.copyWith(messages: List.unmodifiable(messages)));
        }
        // Queued turns were explicitly submitted by the user before process
        // death. Do not replay a request that may already have been charged.
        for (var i = 1; i < messages.length; i++) {
          if (messages[i].role == 'assistant' && messages[i].status == 'queued' &&
              messages[i - 1].role == 'user') {
            restoredJobs.add((messages[i - 1].createdAt ?? thread.createdAt,
                _PendingReply(thread.id, messages[i].id!, messages[i - 1].id!,
                    prepared: true)));
          }
        }
        if (repaired) await _repository.upsertConversation(threadById(thread.id)!);
      }
      restoredJobs.sort((a, b) => a.$1.compareTo(b.$1));
      for (final entry in restoredJobs) { _pending.add(entry.$2); }
      ready = true;
      error = null;
      notifyListeners();
      unawaited(_drain());
    } catch (e) {
      error = '$e';
      notifyListeners();
      _loading = null;
      rethrow;
    }
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_serialId++}';

  void _sort() => _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _replace(ChatThread thread) {
    final index = _threads.indexWhere((t) => t.id == thread.id);
    if (index < 0) {
      _threads.add(thread);
    } else {
      _threads[index] = thread;
    }
    _sort();
    notifyListeners();
  }

  String _title(String text) {
    final words = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final chars = words.runes.toList();
    return String.fromCharCodes(chars.take(45)) + (chars.length > 45 ? '…' : '');
  }

  void newChat() {
    _activeId = null;
    setDraft('');
    notifyListeners();
  }

  void openChat(String id) {
    if (threadById(id) == null) return;
    _activeId = id;
    notifyListeners();
  }

  void setDraft(String value) {
    final id = _activeId ?? '__new__';
    _drafts[id] = value;
    _draftTimers[id]?.cancel();
    _draftTimers[id] = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _repository.saveDraft(id, _drafts[id] ?? '');
      } catch (e) {
        error = 'Не удалось сохранить черновик: $e';
        notifyListeners();
      }
    });
  }

  Future<void> rename(String threadId, String title) async {
    final thread = threadById(threadId);
    if (thread == null || title.trim().isEmpty) return;
    final updated = thread.copyWith(title: title.trim());
    await _repository.upsertConversation(updated);
    _replace(updated);
  }

  Future<void> delete(String threadId) async {
    if (_current?.threadId == threadId) {
      throw StateError('Сначала останови ответ в этом диалоге');
    }
    await _repository.deleteConversation(threadId);
    _threads.removeWhere((thread) => thread.id == threadId);
    _pending.removeWhere((job) => job.threadId == threadId);
    if (_activeId == threadId) {
      _activeId = _threads.isEmpty ? null : _threads.first.id;
    }
    _drafts.remove(threadId);
    _draftTimers.remove(threadId)?.cancel();
    notifyListeners();
  }

  /// The user can submit additional turns while another reply streams. Only
  /// one engine request is ever active, including across multiple threads.
  Future<void> send(String input) async {
    final question = input.trim();
    if (!ready || question.isEmpty) return;
    if (!_gateway.available && !_core.canHandle(question)) {
      throw StateError('Сначала запусти ИИ. Без модели доступны только инструменты.');
    }
    final now = DateTime.now();
    final id = _activeId ?? _newId();
    final old = threadById(id);
    final user = AiMessage(id: _newId(), role: 'user', text: question,
      createdAt: now, status: 'queued');
    final assistant = AiMessage(id: _newId(), role: 'assistant', text: '',
      createdAt: now, status: 'queued');
    final thread = old == null
        ? ChatThread(id: id, title: _title(question), createdAt: now,
            updatedAt: now, messages: [user, assistant])
        : old.copyWith(updatedAt: now,
            messages: [...old.messages, user, assistant]);
    _activeId = id;
    _replace(thread);
    final job = _PendingReply(id, assistant.id!, user.id!);
    _pending.add(job);
    notifyListeners();
    // A durable snapshot is required BEFORE hitting a paid/cloud provider.
    try {
      await _repository.upsertConversation(thread);
    } catch (e) {
      _pending.remove(job);
      final current = threadById(id);
      if (current != null) {
        _setStatus(id, assistant.id!, 'failed');
      }
      unawaited(_drain());
      error = 'Не удалось сохранить запрос: $e';
      notifyListeners();
      rethrow;
    }
    // Explicit "remember" commands must be stored before composing the
    // very first prompt that could use them; ordinary turns are a no-op.
    try {
      await _memory.captureExplicit(question);
    } catch (e) {
      error = 'Не удалось сохранить память: $e';
      notifyListeners();
    }
    job.prepared = true;
    notifyListeners();
    unawaited(_drain());
  }

  void _setStatus(String threadId, String messageId, String status,
      {String? text, String? modelId}) {
    final thread = threadById(threadId);
    if (thread == null) return;
    final next = thread.messages.map((m) => m.id == messageId
        ? m.copyWith(status: status, text: text, modelId: modelId) : m).toList();
    _replace(thread.copyWith(updatedAt: DateTime.now(),
      messages: List.unmodifiable(next)));
  }

  Future<void> _saveThread(String id) async {
    final thread = threadById(id);
    if (thread != null) await _repository.upsertConversation(thread);
  }

  void _schedulePartialSave(String threadId) {
    if (_partialSaveTimer?.isActive ?? false) return;
    _partialSaveTimer = Timer(const Duration(seconds: 1), () async {
      try {
        await _saveThread(threadId);
      } catch (e) {
        error = 'Не удалось сохранить часть ответа: $e';
        notifyListeners();
      }
    });
  }

  Future<void> _drain() async {
    if (_running || !ready) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final job = _pending.first;
        if (!job.prepared) break;
        final thread = threadById(job.threadId);
        if (thread == null) {
          _pending.removeFirst();
          continue;
        }
        final userIndex = thread.messages.indexWhere((m) => m.id == job.userId);
        final assistantIndex = thread.messages.indexWhere((m) => m.id == job.assistantId);
        if (userIndex < 0 || assistantIndex < 0 ||
            thread.messages[assistantIndex].status != 'queued') {
          _pending.removeFirst();
          continue;
        }
        final question = thread.messages[userIndex].text;
        if (!_gateway.available && !_core.canHandle(question)) break;
        _pending.removeFirst();
        _current = job;
        _cancelRequested = false;
        _setStatus(job.threadId, job.userId, 'completed');
        _setStatus(job.threadId, job.assistantId, 'generating',
            modelId: _core.canHandle(question) ? 'tool' : _gateway.modelId);
        try {
          await _saveThread(job.threadId);
          final source = threadById(job.threadId)!;
          // Do not send queued or partial replies to the model context.
          final history = source.messages.take(userIndex + 1)
              .where((m) => m.status == 'completed').toList();
          final safe = _gateway.cloudMode ? _core.cloudSafeHistory(history) : history;
          final recent = safe.length > 48 ? safe.sublist(safe.length - 48) : safe;
          final prompt = buildConversationPrompt(recent, _memory.notes);
          final tool = await _core.tryTool(question);
          if (_cancelRequested) {
            _setStatus(job.threadId, job.assistantId, 'interrupted');
          } else if (tool != null) {
            _setStatus(job.threadId, job.assistantId, 'completed', text: tool.message);
          } else {
            var response = '';
            final repaint = Stopwatch()..start();
            await for (final chunk in _gateway.reply(prompt)) {
              response += chunk;
              if (repaint.elapsedMilliseconds >= 50) {
                repaint.reset();
                _setStatus(job.threadId, job.assistantId, 'generating', text: response);
                _schedulePartialSave(job.threadId);
              }
            }
            _setStatus(job.threadId, job.assistantId,
              _cancelRequested ? 'interrupted' : (response.isEmpty ? 'failed' : 'completed'),
              text: response);
          }
        } catch (e) {
          // Retain partial output instead of dropping a failed reply.
          _setStatus(job.threadId, job.assistantId,
              _cancelRequested ? 'interrupted' : 'failed');
          if (!_cancelRequested) {
            error = 'Ошибка ответа: $e';
            notifyListeners();
          }
        } finally {
          _partialSaveTimer?.cancel();
          _partialSaveTimer = null;
          try {
            await _saveThread(job.threadId);
          } catch (e) {
            error = 'Ответ получен, но сохранение не удалось: $e';
            notifyListeners();
          }
          _current = null;
          notifyListeners();
        }
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_current == null) return;
    _cancelRequested = true;
    await _gateway.stop();
  }

  Future<void> retry(String assistantId) async {
    for (final thread in _threads) {
      final i = thread.messages.indexWhere((m) => m.id == assistantId);
      if (i < 1 || thread.messages[i - 1].role != 'user') continue;
      if (!const {'failed', 'interrupted'}.contains(thread.messages[i].status)) return;
      _setStatus(thread.id, assistantId, 'queued', text: '');
      await _saveThread(thread.id);
      _pending.add(_PendingReply(thread.id, assistantId,
          thread.messages[i - 1].id!, prepared: true));
      notifyListeners();
      unawaited(_drain());
      return;
    }
  }

  @override
  void dispose() {
    _partialSaveTimer?.cancel();
    for (final timer in _draftTimers.values) { timer.cancel(); }
    super.dispose();
  }
}

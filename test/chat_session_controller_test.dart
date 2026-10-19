import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/ai/ai_engine.dart';
import 'package:moy_ai/src/core/baboon/baboon_core.dart';
import 'package:moy_ai/src/core/chat/chat_session_controller.dart';
import 'package:moy_ai/src/core/knowledge/knowledge_repository.dart';
import 'package:moy_ai/src/core/memory/conversation_repository.dart';

class FakeRepo implements ConversationRepository {
  final Map<String, ChatThread> stored = {};
  final Map<String, String> drafts = {};
  final List<String> writes = [];
  @override
  Future<List<ChatThread>> loadConversations() async => stored.values.toList();
  @override
  Future<void> saveConversations(List<ChatThread> conversations) async {
    stored..clear()..addEntries(conversations.map((t) => MapEntry(t.id, t)));
  }
  @override
  Future<void> upsertConversation(ChatThread thread) async {
    stored[thread.id] = thread;
    writes.add(thread.messages.last.status);
  }
  @override
  Future<void> deleteConversation(String id) async { stored.remove(id); }
  @override
  Future<Map<String, String>> loadDrafts() async => Map.of(drafts);
  @override
  Future<void> saveDraft(String id, String text) async { drafts[id] = text; }
  @override
  Future<List<MemoryNote>> loadMemory() async => [];
  @override
  Future<void> saveMemory(List<MemoryNote> notes) async {}
}

class FakeMemory implements ChatMemoryGateway {
  @override
  List<MemoryNote> get notes => const [];
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<void> captureExplicit(String message) async {}
}

class FakeGateway implements ChatReplyGateway {
  bool enabled = true;
  final Completer<void> release = Completer<void>();
  final List<List<AiMessage>> prompts = [];
  int running = 0;
  int maxRunning = 0;
  @override
  bool get available => enabled;
  @override
  bool get cloudMode => false;
  @override
  String get modelId => 'fake/echo';
  @override
  Stream<String> reply(List<AiMessage> prompt) async* {
    prompts.add(prompt);
    running++;
    if (running > maxRunning) maxRunning = running;
    await release.future;
    yield 'Ответ ${prompts.length}';
    running--;
  }
  @override
  Future<void> stop() async {
    if (!release.isCompleted) release.complete();
  }
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 15));

void main() {
  test('New message metadata survives legacy JSON conversion', () {
    final original = ChatThread(
      id: '1', title: 'Пример',
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
      messages: [AiMessage(id: 'm1', role: 'assistant', text: 'Привет',
        status: 'interrupted', modelId: 'fake/model',
        createdAt: DateTime.utc(2026))],
    );
    final restored = ChatThread.fromJson(original.toJson());
    expect(restored.messages.single.id, 'm1');
    expect(restored.messages.single.status, 'interrupted');
    expect(restored.messages.single.modelId, 'fake/model');
    final old = ChatThread.fromJson({
      'id': 'old', 'title': 'Старый чат',
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'messages': [{'role': 'user', 'text': 'Вопрос'}],
    });
    expect(old.messages.single.id, 'old:legacy:0');
    expect(old.messages.single.status, 'completed');
  });

  test('Queue runs serially and persists before calling provider', () async {
    final repo = FakeRepo();
    final gateway = FakeGateway();
    final session = ChatSessionController(
      repository: repo, gateway: gateway, memory: FakeMemory(),
      core: BaboonCore(knowledge: KnowledgeRepository.instance));
    await session.ensureLoaded();
    await session.send('Первый вопрос');
    await session.send('Второй вопрос');
    await tick();
    expect(session.queuedCount, 1);
    expect(gateway.prompts.length, 1);
    expect(repo.writes, contains('generating'));
    expect(repo.stored.values.single.messages.length, 4);
    gateway.release.complete();
    await tick();
    await tick();
    expect(gateway.maxRunning, 1);
    expect(gateway.prompts.length, 2);
    expect(session.messages.where((m) => m.role == 'assistant')
      .map((m) => m.status), everyElement('completed'));
    session.dispose();
  });

  test('Restored generating reply is interrupted rather than duplicated', () async {
    final repo = FakeRepo();
    final now = DateTime.utc(2026);
    repo.stored['old'] = ChatThread(
      id: 'old', title: 'Проверка', createdAt: now, updatedAt: now,
      messages: [
        AiMessage(id: 'u', role: 'user', text: 'Вопрос'),
        AiMessage(id: 'a', role: 'assistant', text: 'Начало', status: 'generating'),
      ],
    );
    final gateway = FakeGateway();
    final session = ChatSessionController(
      repository: repo, gateway: gateway, memory: FakeMemory(),
      core: BaboonCore(knowledge: KnowledgeRepository.instance));
    await session.ensureLoaded();
    expect(session.messages.last.status, 'interrupted');
    expect(session.messages.last.text, 'Начало');
    expect(gateway.prompts, isEmpty);
    expect(repo.stored['old']!.messages.last.status, 'interrupted');
    session.dispose();
  });
}

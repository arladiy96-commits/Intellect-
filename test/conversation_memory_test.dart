import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/ai/ai_engine.dart';
import 'package:moy_ai/src/core/memory/conversation_repository.dart';

void main() {
  test('Chat serialization preserves roles, text, and title', () {
    final thread = ChatThread(
      id: 'chat-1',
      title: 'Вопрос про математику',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 2),
      messages: const [
        AiMessage(role: 'user', text: 'Привет'),
        AiMessage(role: 'assistant', text: 'Здравствуйте!'),
      ],
    );
    final restored = ChatThread.fromJson(thread.toJson());
    expect(restored.title, 'Вопрос про математику');
    expect(restored.messages.map((m) => m.role), ['user', 'assistant']);
    expect(restored.messages.last.text, 'Здравствуйте!');
    expect(restored.updatedAt, DateTime.utc(2026, 10, 2));
  });

  test('Only explicitly saved notes are sent as system context', () {
    const dialogue = [AiMessage(role: 'user', text: 'Чему равно 2+2?')];
    final empty = buildConversationPrompt(dialogue, []);
    expect(empty.length, 1);
    final withMemory = buildConversationPrompt(dialogue, [
      const MemoryNote(id: '1', text: 'Объясняй по шагам'),
    ]);
    expect(withMemory.length, 2);
    expect(withMemory.first.role, 'system');
    expect(withMemory.first.text, contains('Объясняй по шагам'));
    expect(withMemory.last.text, 'Чему равно 2+2?');
  });

  test('Invalid roles are rejected rather than persisted as valid chats', () {
    final now = DateTime.utc(2026).toIso8601String();
    expect(
      () => ChatThread.fromJson({
        'id': 'x', 'title': 'x', 'createdAt': now, 'updatedAt': now,
        'messages': [{'role': 'unknown', 'text': 'Hi'}],
      }),
      throwsFormatException,
    );
  });
}

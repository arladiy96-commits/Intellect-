import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/ai/ai_engine.dart';
import 'package:moy_ai/src/core/memory/conversation_repository.dart';

void main() {
  test('Legacy memory.v1 JSON remains readable', () {
    final restored = MemoryNote.fromJson({'id': 'old', 'text': 'Моя модель Qwen'});
    expect(restored.text, 'Моя модель Qwen');
    expect(restored.category, 'other');
    expect(restored.pinned, isFalse);
    expect(restored.source, 'manual');
  });

  test('Category and pinned flag survive JSON round-trip', () {
    final now = DateTime.utc(2026, 10, 18);
    final note = MemoryNote(
      id: '123', text: 'Проект Мельница', category: 'projects',
      pinned: true, source: 'explicit', createdAt: now,
    );
    final restored = MemoryNote.fromJson(note.toJson());
    expect(restored.pinned, isTrue);
    expect(restored.category, 'projects');
    expect(restored.createdAt, now);
    expect(restored.source, 'explicit');
  });

  test('Only explicit memory commands are captured automatically', () {
    expect(extractExplicitMemory('Запомни, что я использую Flutter'),
        'я использую Flutter');
    expect(extractExplicitMemory('Сохрани в память: мой проект Бабуин'),
        'мой проект Бабуин');
    expect(extractExplicitMemory('А что такое Flutter?'), isNull);
    expect(extractExplicitMemory('Запомни'), isNull);
  });

  test('Project-specific note wins over unrelated memory', () {
    final notes = [
      const MemoryNote(id: 'first', text: 'У меня есть собака и кот'),
      const MemoryNote(id: 'second', text: 'Проект Мельница создаётся на Flutter', category: 'projects'),
    ];
    const messages = [AiMessage(role: 'user', text: 'Расскажи про проект Мельница')];
    final prompt = buildConversationPrompt(messages, notes);
    expect(prompt.first.role, 'system');
    expect(prompt.first.text.indexOf('Мельница') < prompt.first.text.indexOf('собака'), isTrue);
    expect(prompt.last.text, messages.last.text);
  });

  test('Memory is excluded from prompt when empty', () {
    const messages = [AiMessage(role: 'user', text: 'Привет')];
    expect(buildConversationPrompt(messages, []), hasLength(1));
  });
}

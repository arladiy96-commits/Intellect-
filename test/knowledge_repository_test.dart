import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/knowledge/knowledge_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Knowledge collections and documents survive app restart', () async {
    final folder = await Directory.systemTemp.createTemp('baboon-knowledge-');
    try {
      final repo = KnowledgeRepository(directoryProvider: () async => folder);
      final collection = await repo.createCollection('Математика 2 класс');
      final doc = await repo.addDocument(collectionId: collection.id,
          title: 'Тема: Уравнения', content: 'Страница 48. Упражнение 7. x + 28 = 65.',
          sourceName: 'Учебник');
      final hits = await repo.search('страница 48');
      expect(hits.length, 1);
      expect(hits.single.document.id, doc.id);
      final restored = KnowledgeRepository(directoryProvider: () async => folder);
      await restored.ensureLoaded();
      expect(restored.collections.any((c) => c.name == 'Математика 2 класс'), isTrue);
      expect(restored.documents.single.sourceName, 'Учебник');
      await restored.updateDocument(doc.id, title: 'Уравнения', content: 'Задание 7. x + 28 = 65.');
      expect((await restored.search('задание')).single.document.title, 'Уравнения');
      await restored.deleteCollection(collection.id);
      expect(restored.documents, isEmpty);
      final afterDelete = KnowledgeRepository(directoryProvider: () async => folder);
      await afterDelete.ensureLoaded();
      expect(afterDelete.documents, isEmpty);
      expect(afterDelete.collections.length, 1);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('Knowledge rejects oversized and blank documents', () async {
    final folder = await Directory.systemTemp.createTemp('baboon-limit-');
    try {
      final repo = KnowledgeRepository(directoryProvider: () async => folder);
      await expectLater(repo.addDocument(collectionId: KnowledgeRepository.generalId,
          title: 'Пусто', content: ' '), throwsArgumentError);
      await expectLater(repo.addDocument(collectionId: KnowledgeRepository.generalId,
          title: 'Много', content: List.filled(KnowledgeRepository.maxDocumentCharacters + 1, 'а').join()),
          throwsArgumentError);
      expect(repo.documents, isEmpty);
    } finally {
      await folder.delete(recursive: true);
    }
  });
}

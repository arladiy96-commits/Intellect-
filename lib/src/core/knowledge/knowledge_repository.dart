import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class KnowledgeCollection {
  const KnowledgeCollection({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, Object> toJson() => {'id': id, 'name': name};
  factory KnowledgeCollection.fromJson(Map<String, dynamic> json) =>
      KnowledgeCollection(id: json['id'] as String, name: json['name'] as String);
}

class KnowledgeDocument {
  const KnowledgeDocument({required this.id, required this.collectionId,
    required this.title, required this.content, required this.sourceName,
    required this.createdAt});
  final String id;
  final String collectionId;
  final String title;
  final String content;
  final String sourceName;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'id': id, 'collectionId': collectionId, 'title': title,
    'content': content, 'sourceName': sourceName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) => KnowledgeDocument(
    id: json['id'] as String,
    collectionId: json['collectionId'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    sourceName: (json['sourceName'] as String?) ?? 'Ручной ввод',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class KnowledgeHit {
  const KnowledgeHit({required this.document, required this.excerpt, required this.score});
  final KnowledgeDocument document;
  final String excerpt;
  final int score;
}

/// Private on-device storage, separate from conversation memory and any cloud
/// provider. It NEVER sends documents to Groq or OpenRouter automatically.
class KnowledgeRepository extends ChangeNotifier {
  KnowledgeRepository({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final KnowledgeRepository instance = KnowledgeRepository();
  static const generalId = 'general';
  static const maxDocumentCharacters = 250000;
  final Future<Directory> Function() _directoryProvider;
  final List<KnowledgeCollection> _collections = [];
  final List<KnowledgeDocument> _documents = [];
  Future<void>? _loading;
  Future<void> _lastWrite = Future<void>.value();
  int _counter = 0;

  List<KnowledgeCollection> get collections => List.unmodifiable(_collections);
  List<KnowledgeDocument> get documents => List.unmodifiable(_documents);

  Future<void> ensureLoaded() => _loading ??= _read();

  Future<File> _file() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}baboon_knowledge_v1.json');
  }

  Future<void> _read() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, dynamic> || json['version'] != 1 ||
            json['collections'] is! List || json['documents'] is! List) {
          throw const FormatException('Неизвестный формат базы знаний');
        }
        final collections = (json['collections'] as List)
            .map((e) => KnowledgeCollection.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        final documents = (json['documents'] as List)
            .map((e) => KnowledgeDocument.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _collections..clear()..addAll(collections);
        _documents..clear()..addAll(documents);
      }
      if (!_collections.any((e) => e.id == generalId)) {
        _collections.insert(0, const KnowledgeCollection(id: generalId, name: 'Общие знания'));
      }
      notifyListeners();
    } catch (_) {
      _loading = null;
      rethrow; // Never overwrite a corrupted database silently.
    }
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  Future<void> _save() {
    final snapshot = jsonEncode({
      'version': 1,
      'collections': _collections.map((e) => e.toJson()).toList(),
      'documents': _documents.map((e) => e.toJson()).toList(),
    });
    final next = _lastWrite.then((_) async {
      final target = await _file();
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      // Rename is atomic on the same Android filesystem.
      await temporary.rename(target.path);
    });
    _lastWrite = next.catchError((Object _) {});
    return next;
  }

  Future<KnowledgeCollection> createCollection(String name) async {
    await ensureLoaded();
    final value = name.trim();
    if (value.isEmpty || value.length > 80) throw ArgumentError('Название: от 1 до 80 символов');
    if (_collections.any((c) => c.name.toLowerCase() == value.toLowerCase())) {
      throw ArgumentError('Коллекция с таким названием уже есть');
    }
    final collection = KnowledgeCollection(id: _id(), name: value);
    _collections.add(collection);
    notifyListeners();
    await _save();
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    await ensureLoaded();
    if (id == generalId) throw StateError('Основную коллекцию удалить нельзя');
    _collections.removeWhere((e) => e.id == id);
    _documents.removeWhere((e) => e.collectionId == id);
    notifyListeners();
    await _save();
  }

  Future<KnowledgeDocument> addDocument({required String collectionId,
      required String title, required String content, String sourceName = 'Ручной ввод'}) async {
    await ensureLoaded();
    if (!_collections.any((c) => c.id == collectionId)) {
      throw ArgumentError('Коллекция не найдена');
    }
    final name = title.trim();
    final text = content.trim();
    if (name.isEmpty || name.length > 160) throw ArgumentError('Название: от 1 до 160 символов');
    if (text.isEmpty) throw ArgumentError('Документ пустой');
    if (text.length > maxDocumentCharacters) {
      throw ArgumentError('Документ слишком большой (макс. $maxDocumentCharacters символов)');
    }
    final doc = KnowledgeDocument(id: _id(), collectionId: collectionId,
      title: name, content: text, sourceName: sourceName, createdAt: DateTime.now());
    _documents.add(doc);
    notifyListeners();
    await _save();
    return doc;
  }

  Future<void> updateDocument(String id, {required String title, required String content}) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == id);
    if (index < 0) throw ArgumentError('Документ не найден');
    final previous = _documents[index];
    final name = title.trim();
    final text = content.trim();
    if (name.isEmpty || name.length > 160 || text.isEmpty ||
        text.length > maxDocumentCharacters) throw ArgumentError('Проверь размер и содержимое');
    _documents[index] = KnowledgeDocument(
      id: previous.id, collectionId: previous.collectionId,
      title: name, content: text, sourceName: previous.sourceName,
      createdAt: previous.createdAt);
    notifyListeners();
    await _save();
  }

  Future<void> deleteDocument(String id) async {
    await ensureLoaded();
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
    await _save();
  }

  static final _wordPattern = RegExp(r'[а-яёa-z0-9]+', caseSensitive: false);
  static final _stopWords = {'найди', 'базе', 'знаниях', 'поиск', 'знаний',
    'про', 'что', 'где', 'для', 'или', 'это', 'есть', 'мой', 'мои', 'как',
    'все', 'всё', 'мне', 'при', 'на', 'из', 'по', 'от'};

  Future<List<KnowledgeHit>> search(String question,
      {String? collectionId, int limit = 8}) async {
    await ensureLoaded();
    final words = _wordPattern.allMatches(question.toLowerCase())
        .map((m) => m.group(0)!)
        .where((word) => !_stopWords.contains(word) && (word.length >= 3 || int.tryParse(word) != null))
        .toSet().toList();
    if (words.isEmpty) return [];
    final result = <KnowledgeHit>[];
    for (final doc in _documents) {
      if (collectionId != null && doc.collectionId != collectionId) continue;
      final title = doc.title.toLowerCase();
      final content = doc.content.toLowerCase();
      var score = 0;
      var first = -1;
      for (final word in words) {
        if (title.contains(word)) score += 5;
        final i = content.indexOf(word);
        if (i >= 0) {
          score += 2;
          if (first < 0 || i < first) first = i;
        }
      }
      if (score == 0) continue;
      final start = first < 0 ? 0 : (first - 60).clamp(0, doc.content.length).toInt();
      final end = (start + 220).clamp(0, doc.content.length).toInt();
      result.add(KnowledgeHit(document: doc, score: score,
        excerpt: '${start > 0 ? '…' : ''}${doc.content.substring(start, end)}${end < doc.content.length ? '…' : ''}'));
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result.take(limit.clamp(1, 30).toInt()).toList();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'conversation_repository.dart';

/// One source of truth for all chat screens, Memory tab and future agents.
/// Keeps the existing memory.v1.json file; no migrations or model reimports.
class SharedMemoryStore extends ChangeNotifier {
  SharedMemoryStore._();
  static final SharedMemoryStore instance = SharedMemoryStore._();

  final _repository = LocalConversationRepository.instance;
  final List<MemoryNote> _notes = [];
  Future<void>? _loading;
  Future<void> _operation = Future<void>.value();

  List<MemoryNote> get notes => List.unmodifiable(_notes);
  bool get loaded => _loading != null;

  Future<void> ensureLoaded() => _loading ??= _readOnce();

  Future<void> _readOnce() async {
    try {
      _notes.addAll(await _repository.loadMemory());
      notifyListeners();
    } catch (_) {
      _loading = null; // Allow retry after a failed read.
      rethrow;
    }
  }

  /// Serialized mutations avoid overwriting a note saved in another tab.
  Future<void> _change(void Function(List<MemoryNote>) action) {
    final pending = Completer<void>();
    _operation = _operation.catchError((Object _) {}).then((_) async {
      try {
        await ensureLoaded();
        final next = List<MemoryNote>.of(_notes);
        action(next);
        await _repository.saveMemory(next);
        _notes..clear()..addAll(next);
        notifyListeners();
        pending.complete();
      } catch (error, trace) {
        pending.completeError(error, trace);
      }
    });
    return pending.future;
  }

  Future<void> save({
    MemoryNote? existing,
    required String text,
    String category = 'other',
    bool pinned = false,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 300) {
      throw ArgumentError('Длина воспоминания должна быть от 1 до 300 символов');
    }
    if (!memoryCategoryValues.contains(category)) category = 'other';
    final now = DateTime.now();
    await _change((next) {
      final note = existing == null
          ? MemoryNote(
              id: now.microsecondsSinceEpoch.toString(),
              text: normalized,
              category: category,
              pinned: pinned,
              createdAt: now,
              updatedAt: now,
            )
          : existing.copyWith(
              text: normalized,
              category: category,
              pinned: pinned,
              updatedAt: now,
            );
      if (existing == null) {
        next.add(note);
      } else {
        final index = next.indexWhere((m) => m.id == existing.id);
        if (index < 0) throw StateError('Воспоминание уже удалено');
        next[index] = note;
      }
    });
  }

  Future<void> remove(String id) => _change((next) {
        next.removeWhere((n) => n.id == id);
      });

  Future<void> setPinned(MemoryNote note, bool pinned) =>
      save(existing: note, text: note.text, category: note.category, pinned: pinned);

  /// Auto-save only when a user *explicitly* asks to remember something.
  /// This avoids inventing facts with a compact local 4B model.
  Future<bool> captureExplicit(String message) async {
    final fact = extractExplicitMemory(message);
    if (fact == null) return false;
    var inserted = false;
    await _change((next) {
      final exists = next.any((n) =>
          n.text.toLowerCase().trim() == fact.toLowerCase().trim());
      if (exists) return;
      final now = DateTime.now();
      next.add(MemoryNote(
        id: now.microsecondsSinceEpoch.toString(),
        text: fact,
        category: suggestMemoryCategory(fact),
        source: 'explicit',
        createdAt: now,
        updatedAt: now,
      ));
      inserted = true;
    });
    return inserted;
  }
}

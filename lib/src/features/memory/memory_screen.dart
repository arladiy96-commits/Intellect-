import 'package:flutter/material.dart';

import '../../core/memory/conversation_repository.dart';
import '../../core/memory/shared_memory_store.dart';

/// Memory belongs to the assistant, not to an individual conversation.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _store = SharedMemoryStore.instance;
  final _search = TextEditingController();
  String _category = 'all';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _init();
  }

  Future<void> _init() async {
    try {
      await _store.ensureLoaded();
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit([MemoryNote? previous]) async {
    final result = await showDialog<_MemoryEdit>(
      context: context,
      builder: (context) => _MemoryEditor(previous: previous),
    );
    if (result == null) return;
    try {
      await _store.save(
        existing: previous,
        text: result.text,
        category: result.category,
        pinned: result.pinned,
      );
    } catch (e) {
      _showError('Не удалось сохранить: $e');
    }
  }

  Future<void> _delete(MemoryNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить воспоминание?'),
        content: const Text('Бабуин перестанет использовать эту запись в новых запросах.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.remove(note.id);
    } catch (e) {
      _showError('Не удалось удалить: $e');
    }
  }

  void _showError(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 40),
        Text('Не удалось открыть память: $_error'),
        TextButton(onPressed: () { setState(() { _error = null; _loading = true; }); _init(); }, child: const Text('Повторить')),
      ]));
    }

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final visible = _store.notes.where((note) {
          if (_category != 'all' && note.category != _category) return false;
          return q.isEmpty || note.text.toLowerCase().contains(q);
        }).toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return (b.updatedAt ?? b.createdAt ?? DateTime(2000))
                .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(2000));
          });
        return Scaffold(
          appBar: ModalRoute.of(context)?.canPop == true
              ? AppBar(title: const Text('Память Бабуина'))
              : null,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Запомнить'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Row(children: [
                Icon(Icons.psychology_alt_outlined,
                    color: Theme.of(context).colorScheme.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text('Память Бабуина',
                    style: Theme.of(context).textTheme.headlineSmall)),
                Text('${_store.notes.length}'),
              ]),
              const SizedBox(height: 8),
              const Text('Общая для всех чатов. Хранится на телефоне и работает без интернета.'),
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.auto_awesome_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Напиши в любом чате «Запомни, что…» — запись сохранится автоматически. '
                    'Остальные факты пока добавляй здесь или долгим нажатием на сообщение.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                ]),
              )),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Найти воспоминание',
                  border: const OutlineInputBorder(),
                  suffixIcon: _search.text.isEmpty ? null : IconButton(
                    onPressed: _search.clear,
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('all', 'Все'),
                  for (final value in memoryCategoryValues)
                    _chip(value, memoryCategoryLabels[value]!),
                ]),
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Column(children: [
                    const Icon(Icons.bookmarks_outlined, size: 52),
                    const SizedBox(height: 12),
                    Text(_store.notes.isEmpty
                      ? 'Пока ничего не сохранено'
                      : 'Нет воспоминаний по запросу'),
                  ]),
                ),
              for (final note in visible)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _edit(note),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              if (note.pinned) ...[
                                const Icon(Icons.push_pin, size: 14),
                                const SizedBox(width: 5),
                              ],
                              Text(memoryCategoryLabels[note.category] ?? 'Другое',
                                  style: Theme.of(context).textTheme.labelMedium),
                            ]),
                            const SizedBox(height: 6),
                            Text(note.text),
                            if (note.source == 'explicit') ...[
                              const SizedBox(height: 6),
                              Text('Сохранено из чата', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ]),
                        ),
                      )),
                      PopupMenuButton<String>(
                        tooltip: 'Действия с воспоминанием',
                        onSelected: (action) async {
                          switch (action) {
                            case 'edit': await _edit(note); return;
                            case 'pin':
                              try { await _store.setPinned(note, !note.pinned); }
                              catch (e) { _showError('$e'); }
                              return;
                            case 'delete': await _delete(note); return;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                          PopupMenuItem(value: 'pin',
                              child: Text(note.pinned ? 'Открепить' : 'Закрепить')),
                          const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                        ],
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String id, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: _category == id,
      onSelected: (_) => setState(() => _category = id),
    ),
  );
}

class _MemoryEdit {
  const _MemoryEdit(this.text, this.category, this.pinned);
  final String text;
  final String category;
  final bool pinned;
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({this.previous});
  final MemoryNote? previous;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  late final TextEditingController _text;
  late String _category;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.previous?.text ?? '');
    _category = widget.previous?.category ?? 'other';
    _pinned = widget.previous?.pinned ?? false;
    _text.addListener(_repaint);
  }

  void _repaint() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_repaint);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.previous == null ? 'Новое воспоминание' : 'Редактировать память'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 300,
        decoration: const InputDecoration(hintText: 'Что Бабуин должен помнить?', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        // The initial category is also valid for migrated v1 memories.
        initialValue: memoryCategoryValues.contains(_category) ? _category : 'other',
        decoration: const InputDecoration(labelText: 'Категория'),
        items: [for (final e in memoryCategoryValues)
          DropdownMenuItem(value: e, child: Text(memoryCategoryLabels[e]!))],
        onChanged: (value) => setState(() => _category = value ?? 'other'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Закрепить'),
        value: _pinned,
        onChanged: (v) => setState(() => _pinned = v),
      ),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(
        onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context,
            _MemoryEdit(_text.text.trim(), _category, _pinned)),
        child: const Text('Сохранить'),
      ),
    ],
  );
}

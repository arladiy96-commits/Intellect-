import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/knowledge/knowledge_repository.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  final _repo = KnowledgeRepository.instance;
  final _search = TextEditingController();
  bool _ready = false;
  bool _busy = false;
  String? _error;
  String _collectionId = KnowledgeRepository.generalId;
  List<KnowledgeHit>? _hits;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _repo.ensureLoaded();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repo.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _notify(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _notify('Ошибка: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName({required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, maxLength: 80,
        decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Сохранить')),
      ],
    ));
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<void> _addCollection() async {
    final name = await _askName(title: 'Новая коллекция');
    if (name == null || !mounted) return;
    await _run(() async {
      final collection = await _repo.createCollection(name);
      if (mounted) setState(() { _collectionId = collection.id; _hits = null; });
    });
  }

  Future<void> _edit({KnowledgeDocument? document}) async {
    final titleController = TextEditingController(text: document?.title ?? '');
    final contentController = TextEditingController(text: document?.content ?? '');
    final form = await showDialog<({String title, String content})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(document == null ? 'Добавить знание' : 'Изменить документ'),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, maxLength: 160,
              decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: contentController, minLines: 5, maxLines: 12,
              decoration: const InputDecoration(labelText: 'Содержание',
                alignLabelWithHint: true, border: OutlineInputBorder())),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, (
            title: titleController.text, content: contentController.text)),
            child: const Text('Сохранить')),
        ],
      ),
    );
    titleController.dispose();
    contentController.dispose();
    if (form == null || !mounted) return;
    await _run(() async {
      if (document == null) {
        await _repo.addDocument(collectionId: _collectionId, title: form.title,
          content: form.content);
      } else {
        await _repo.updateDocument(document.id, title: form.title, content: form.content);
      }
      if (mounted) setState(() => _hits = null);
      _notify('Знание сохранено на телефоне');
    });
  }

  Future<void> _importFile() => _run(() async {
    final file = await FilePicker.pickFile(type: FileType.custom,
      allowedExtensions: ['txt', 'md']);
    if (file == null) return;
    final size = await file.length();
    if (size == null || size > 600000) {
      throw const FormatException('Максимальный размер текстового файла — 600 КБ');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 600000) {
      throw const FormatException('Файл слишком большой (более 600 КБ)');
    }
    final content = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    await _repo.addDocument(collectionId: _collectionId, title: file.name,
      content: content, sourceName: file.name);
    if (mounted) setState(() => _hits = null);
    _notify('Файл «${file.name}» добавлен');
  });

  Future<void> _searchKnowledge() => _run(() async {
    final results = await _repo.search(_search.text);
    if (mounted) setState(() => _hits = results);
  });

  Future<void> _removeDoc(KnowledgeDocument document) async {
    final ok = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text('«${document.title}» будет удалён из базы на этом устройстве.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ));
    if (ok != true || !mounted) return;
    await _run(() async {
      await _repo.deleteDocument(document.id);
      if (mounted) setState(() => _hits = null);
    });
  }

  Future<void> _removeCollection() async {
    if (_collectionId == KnowledgeRepository.generalId) return;
    final collection = _repo.collections.where((c) => c.id == _collectionId).firstOrNull;
    if (collection == null) return;
    final count = _repo.documents.where((d) => d.collectionId == _collectionId).length;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить коллекцию?'),
      content: Text('«${collection.name}» и $count документов будут удалены с телефона.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (ok != true || !mounted) return;
    final id = _collectionId;
    await _run(() async {
      await _repo.deleteCollection(id);
      if (mounted) setState(() {
        _collectionId = KnowledgeRepository.generalId;
        _hits = null;
      });
    });
  }

  Widget _documentTile(KnowledgeDocument doc, {String? excerpt}) => Card(
    child: ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(excerpt ?? doc.content,
        maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(doc.title),
        content: SizedBox(width: 550, child: SingleChildScrollView(
          child: SelectableText(doc.content))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      )),
      trailing: PopupMenuButton<String>(
        tooltip: 'Действия с документом',
        enabled: !_busy,
        onSelected: (action) {
          if (action == 'edit') unawaited(_edit(document: doc));
          if (action == 'delete') unawaited(_removeDoc(doc));
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Редактировать')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(
      appBar: AppBar(title: const Text('База знаний')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Text('Не удалось открыть базу: $_error'))),
    );
    if (!_ready) return Scaffold(
      appBar: AppBar(title: const Text('База знаний')),
      body: const Center(child: CircularProgressIndicator()),
    );
    final currentDocs = _repo.documents.where((d) => d.collectionId == _collectionId).toList();
    final count = _repo.documents.length;
    return Scaffold(
      appBar: AppBar(title: const Text('База знаний'), actions: [
        IconButton(tooltip: 'Новая коллекция', onPressed: _busy ? null : _addCollection,
          icon: const Icon(Icons.create_new_folder_outlined)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('$count документов · ${_repo.collections.length} коллекций',
          style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        const Text('Знания хранятся на телефоне и не отправляются в облако автоматически.'),
        const SizedBox(height: 16),
        Text('Коллекции', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final collection in _repo.collections)
            ChoiceChip(label: Text(collection.name),
              selected: collection.id == _collectionId,
              onSelected: _busy ? null : (_) => setState(() {
                _collectionId = collection.id;
                _hits = null;
              })),
          ActionChip(label: const Text('+ Новая'),
            onPressed: _busy ? null : _addCollection),
        ]),
        if (_collectionId != KnowledgeRepository.generalId)
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: _busy ? null : _removeCollection,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить коллекцию'))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.note_add_outlined), label: const Text('Добавить текст')),
          OutlinedButton.icon(onPressed: _busy ? null : _importFile,
            icon: const Icon(Icons.upload_file_outlined), label: const Text('Импорт TXT / MD')),
        ]),
        const SizedBox(height: 8),
        Text('PDF, DOCX, OCR фотографий и смысловой поиск — следующие обработчики.',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: TextField(controller: _search, enabled: !_busy,
            decoration: const InputDecoration(
              hintText: 'Поиск по всем коллекциям', prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder()),
            onSubmitted: (_) => _searchKnowledge())),
          const SizedBox(width: 8),
          IconButton.filled(icon: const Icon(Icons.search), tooltip: 'Найти',
            onPressed: _busy ? null : _searchKnowledge),
          if (_hits != null) IconButton(tooltip: 'Сбросить поиск',
            icon: const Icon(Icons.close), onPressed: () {
              _search.clear(); setState(() => _hits = null);
            }),
        ]),
        const SizedBox(height: 18),
        Text(_hits == null ? 'Документы в коллекции ($count${currentDocs.length == count ? '' : ', здесь ${currentDocs.length}'})'
          : 'Результаты поиска (${_hits!.length})',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (_hits == null && currentDocs.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: Text('Пока пусто. Добавь документ или создай коллекцию.')),
        if (_hits != null && _hits!.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: Text('Точных совпадений нет. Уточни запрос.')),
        if (_hits != null)
          for (final hit in _hits!) _documentTile(hit.document, excerpt: hit.excerpt)
        else
          for (final doc in currentDocs.reversed) _documentTile(doc),
      ]),
    );
  }
}

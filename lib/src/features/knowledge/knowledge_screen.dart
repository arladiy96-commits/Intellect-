import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/knowledge/knowledge_repository.dart';
import '../../ui/baboon_style.dart';
import 'knowledge_editor_screen.dart';
import 'textbook_preview_screen.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});
  @override State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  final repo = KnowledgeRepository.instance;
  final search = TextEditingController();
  String filter = 'Все';
  String? selectedCollection;
  String? error;
  bool ready = false;
  bool busy = false;
  List<KnowledgeHit>? hits;

  @override void initState() {
    super.initState();
    repo.addListener(_changed);
    unawaited(_load());
  }
  Future<void> _load() async {
    try {
      await repo.ensureLoaded();
      if (mounted) { setState(() => ready = true); }
    } catch (e) {if (mounted) { setState(() => error = '$e'); }}
  }
  void _changed() { if (mounted) { setState(() {}); } }
  @override void dispose() {
    repo.removeListener(_changed); search.dispose(); super.dispose();
  }
  void _notify(String s) {
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  }
  Future<void> _run(Future<void> Function() action) async {
    if (busy) { return; }
    setState(() => busy = true);
    try {await action();} catch (e) { _notify('Ошибка: $e'); }
    finally {if (mounted) { setState(() => busy = false); }}
  }
  Future<void> _newCollection([String? preset]) async {
    final controller = TextEditingController(text: preset ?? '');
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Новая коллекция'),
      content: TextField(controller: controller, maxLength: 80, autofocus: true,
        decoration: const InputDecoration(labelText: 'Название')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Создать')),
      ],
    ));
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) { return; }
    await _run(() async {
      final c = await repo.createCollection(name);
      if (mounted) { setState(() => selectedCollection = c.id); }
    });
  }
  Future<void> _openEditor({KnowledgeDocument? document}) async {
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => KnowledgeEditorScreen(
        initialCollectionId: selectedCollection ?? KnowledgeRepository.generalId,
        document: document)));
  }
  Future<void> _removeDoc(KnowledgeDocument doc) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить документ?'),
      content: Text('«${doc.title}» будет удалён с этого телефона.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (ok == true) { await _run(() => repo.deleteDocument(doc.id)); }
  }
  Future<void> _removeCollection(KnowledgeCollection c) async {
    if (c.id == KnowledgeRepository.generalId) { return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить коллекцию?'),
      content: const Text('Все документы коллекции также будут удалены.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (ok == true) {
      await _run(() async {
        await repo.deleteCollection(c.id);
        if (mounted) { setState(() => selectedCollection = null); }
      });
    }
  }
  Future<void> _search() async {
    if (search.text.trim().isEmpty) {setState(() => hits = null);return;}
    await _run(() async {
      final values = await repo.search(search.text.trim());
      if (mounted) { setState(() => hits = values); }
    });
  }

  static const _suggested = [
    'Математика 2 класс', 'Русский язык 2 класс', 'Программирование',
    'Рабочие документы', 'Личные заметки', 'Другие предметы',
  ];

  bool _matchesFilter(String name) {
    final n = name.toLowerCase();
    switch (filter) {
      case 'Учебники': return n.contains('учеб') || n.contains('матем') || n.contains('русск') || n.contains('предмет');
      case 'Документы': return n.contains('документ') || n.contains('работ');
      case 'Проекты': return n.contains('проект') || n.contains('программ');
      default: return true;
    }
  }

  @override Widget build(BuildContext context) {
    if (error != null) { return Center(child: Text('Ошибка базы знаний: $error')); }
    if (!ready) { return const Center(child: CircularProgressIndicator()); }
    final collections = repo.collections.where((c) => _matchesFilter(c.name)).toList();
    final visible = repo.documents.where((d) =>
      selectedCollection == null || d.collectionId == selectedCollection).toList();
    const colors = [Color(0xFFD59A48), Color(0xFFBA7FEA), Color(0xFF5AB6A0), Color(0xFF68A7EA)];
    return ListView(padding: const EdgeInsets.fromLTRB(15, 15, 15, 26), children: [
      Row(children: [
        const Expanded(child: BaboonTitle('База знаний')),
        IconButton(tooltip: 'Добавить знание', onPressed: () => _openEditor(),
          icon: const Icon(Icons.add_rounded, size: 29)),
        IconButton(tooltip: 'Меню приложения',
          onPressed: () {
            final scaffold = Scaffold.maybeOf(context);
            if (scaffold?.widget.drawer != null) {
              scaffold?.openDrawer();
            } else {
              _newCollection();
            }
          },
          icon: const Icon(Icons.menu_rounded)),
      ]),
      const SizedBox(height: 12),
      TextField(controller: search, onChanged: (_) {if (search.text.isEmpty) { setState(() => hits = null); }},
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(isDense: true,
          prefixIcon: const Icon(Icons.search), hintText: 'Поиск по базе знаний…',
          suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search))),
      const SizedBox(height: 13),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final f in const ['Все', 'Учебники', 'Документы', 'Проекты']) ...[
          ChoiceChip(selected: filter == f, label: Text(f),
            onSelected: (_) => setState(() => filter = f)),
          const SizedBox(width: 6),
        ],
      ])),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: () => _newCollection(),
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
          label: const Text('Новая коллекция'))),
      const SizedBox(height: 5),
      if (selectedCollection != null)
        Row(children: [
          TextButton.icon(onPressed: () => setState(() => selectedCollection = null),
            icon: const Icon(Icons.arrow_back), label: const Text('Все коллекции')),
        ]),
      if (hits != null) ...[
        Text('Результаты поиска (${hits!.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final hit in hits!) _documentCard(hit.document, hit.excerpt),
        if (hits!.isEmpty) const Text('Совпадений нет', style: TextStyle(color: BaboonColors.muted)),
        const SizedBox(height: 10),
      ] else ...[
        if (selectedCollection == null)
          for (var i = 0; i < collections.length; i++) ...[
            _folderCard(collections[i], colors[i % colors.length]),
            const SizedBox(height: 8),
          ],
        if (selectedCollection == null)
          for (var i = 0; i < _suggested.length; i++)
            if (!repo.collections.any((c) =>
                c.name.toLowerCase() == _suggested[i].toLowerCase()) &&
                _matchesFilter(_suggested[i])) ...[
              _suggestedCard(_suggested[i], colors[i % colors.length]),
              const SizedBox(height: 8),
            ],
        if (selectedCollection == null && collections.isEmpty) const Padding(
          padding: EdgeInsets.all(14), child: Text('Пока нет коллекций. Нажми +, чтобы добавить.',
            style: TextStyle(color: BaboonColors.muted))),
        const SizedBox(height: 7),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(selectedCollection == null ? 'Недавние документы' : 'Документы коллекции',
            style: Theme.of(context).textTheme.titleMedium),
          Text('${visible.length}', style: const TextStyle(color: BaboonColors.muted)),
        ]),
        const SizedBox(height: 7),
        for (final doc in visible.reversed.take(30)) _documentCard(doc),
        if (visible.isEmpty) const Text('Здесь ещё нет документов.',
          style: TextStyle(color: BaboonColors.muted, fontSize: 12)),
      ],
      const SizedBox(height: 18),
      BaboonPanel(onTap: () => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => const TextbookPreviewScreen())),
        child: const Row(children: [
          Icon(Icons.auto_stories_outlined, color: BaboonColors.gold),
          SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Просмотр учебника', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Образец интерфейса · PDF подключим позже',
              style: TextStyle(color: BaboonColors.muted, fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: BaboonColors.muted),
        ])),
      const SizedBox(height: 13),
      const Text('Знания хранятся на устройстве. Текущая версия поддерживает текст и TXT/MD.',
        style: TextStyle(color: BaboonColors.muted, fontSize: 11)),
    ]);
  }

  Widget _suggestedCard(String name, Color color) => BaboonPanel(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    onTap: () => _newCollection(name),
    child: Row(children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(9)),
        child: Icon(Icons.folder_rounded, color: color, size: 29)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const Text('Создать коллекцию',
          style: TextStyle(fontSize: 11, color: BaboonColors.muted)),
      ])),
      const Icon(Icons.chevron_right, size: 18, color: BaboonColors.muted),
    ]),
  );

  Widget _folderCard(KnowledgeCollection collection, Color color) {
    final count = repo.documents.where((d) => d.collectionId == collection.id).length;
    return BaboonPanel(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      onTap: () => setState(() {selectedCollection = collection.id;hits = null;}),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.folder_rounded, color: color, size: 29)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(collection.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text('$count документов', style: const TextStyle(fontSize: 11, color: BaboonColors.muted)),
        ])),
        if (collection.id != KnowledgeRepository.generalId)
          PopupMenuButton<String>(tooltip: 'Коллекция',
            onSelected: (v) {if (v == 'delete') { _removeCollection(collection); }},
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Удалить коллекцию')),
            ],
            icon: const Icon(Icons.more_vert, size: 17, color: BaboonColors.muted))
        else const Icon(Icons.chevron_right, size: 18, color: BaboonColors.muted),
      ]));
  }

  Widget _documentCard(KnowledgeDocument doc, [String? excerpt]) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: BaboonPanel(padding: const EdgeInsets.all(10),
      onTap: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(doc.title), content: SingleChildScrollView(child: SelectableText(doc.content)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      )),
      child: Row(children: [
        const Icon(Icons.description_outlined, color: BaboonColors.gold),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(excerpt ?? doc.content, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BaboonColors.muted, fontSize: 11)),
        ])),
        PopupMenuButton<String>(onSelected: (v) {
          if (v == 'edit') { _openEditor(document: doc); }
          if (v == 'delete') { _removeDoc(doc); }
        }, itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Редактировать')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ]),
      ])),
  );
}

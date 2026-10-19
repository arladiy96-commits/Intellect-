import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/knowledge/knowledge_repository.dart';
import '../../ui/baboon_style.dart';

class KnowledgeEditorScreen extends StatefulWidget {
  const KnowledgeEditorScreen({super.key, this.initialCollectionId = KnowledgeRepository.generalId,
    this.document});
  final String initialCollectionId;
  final KnowledgeDocument? document;
  @override State<KnowledgeEditorScreen> createState() => _KnowledgeEditorScreenState();
}

class _KnowledgeEditorScreenState extends State<KnowledgeEditorScreen> {
  final repo = KnowledgeRepository.instance;
  late final TextEditingController title = TextEditingController(text: widget.document?.title ?? '');
  late final TextEditingController content = TextEditingController(text: widget.document?.content ?? '');
  final description = TextEditingController();
  late String collectionId = widget.document?.collectionId ?? widget.initialCollectionId;
  String mode = 'Текст';
  bool busy = false;

  @override void dispose() {title.dispose();content.dispose();description.dispose();super.dispose();}
  void _message(String value) {if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }}

  Future<void> _file() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: ['txt', 'md']);
      if (file == null) { return; }
      final length = await file.length();
      if (length == null || length > 600000) {
        _message('Поддерживаются текстовые файлы до 600 КБ'); return;
      }
      final data = await file.readAsBytes();
      if (data.length > 600000) { _message('Слишком большой файл'); return; }
      setState(() {
        title.text = file.name;
        content.text = utf8.decode(data).replaceFirst('\uFEFF', '');
        mode = 'Файл';
      });
    } catch (e) { _message('Не удалось прочитать файл: $e'); }
  }

  Future<void> _save() async {
    if (busy) { return; }
    if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
      _message('Нужны название и текст документа'); return;
    }
    setState(() => busy = true);
    try {
      final value = description.text.trim().isEmpty
        ? content.text : '${description.text.trim()}\n\n${content.text}';
      if (widget.document == null) {
        await repo.addDocument(collectionId: collectionId, title: title.text.trim(),
          content: value, sourceName: mode == 'Файл' ? title.text.trim() : 'Ручной ввод');
      } else {
        await repo.updateDocument(widget.document!.id,
          title: title.text.trim(), content: value);
      }
      if (mounted) { Navigator.pop(context, true); }
    } catch (e) {
      _message('Ошибка сохранения: $e');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  @override Widget build(BuildContext context) {
    final collections = repo.collections;
    if (!collections.any((e) => e.id == collectionId)) { collectionId = KnowledgeRepository.generalId; }
    return Scaffold(
      appBar: AppBar(title: Text(widget.document == null ? 'Добавить знания' : 'Изменить документ')),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final tab in const ['Файл', 'Фото', 'Текст', 'Ссылка']) ...[
              ChoiceChip(label: Text(tab), selected: mode == tab,
                onSelected: (_) {
                  if (tab == 'Файл') { _file(); return; }
                  if (tab == 'Фото' || tab == 'Ссылка') {
                    baboonSoon(context, tab == 'Фото' ? 'Распознавание фото' : 'Импорт ссылок',
                      'Этот способ добавления знаний подключим позже. Сейчас работают текст и TXT/MD.');
                    return;
                  }
                  setState(() => mode = tab);
                }),
              const SizedBox(width: 8),
            ],
          ])),
          const SizedBox(height: 14),
          if (widget.document == null)
            BaboonPanel(onTap: _file, child: const SizedBox(height: 105,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.upload_file_outlined, size: 32, color: BaboonColors.gold),
                SizedBox(height: 8),
                Text('Выбери файл', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('TXT / MD · до 600 КБ', style: TextStyle(color: BaboonColors.muted)),
              ]))),
          const SizedBox(height: 12),
          TextField(controller: title, maxLength: 160,
            decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 11),
          DropdownButtonFormField<String>(
            initialValue: collectionId,
            isExpanded: true,
            dropdownColor: BaboonColors.surface,
            decoration: const InputDecoration(labelText: 'Категория'),
            items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: widget.document == null ? (v) {if (v != null) { setState(() => collectionId = v); }} : null,
          ),
          const SizedBox(height: 11),
          if (widget.document == null) ...[
            TextField(controller: description, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Описание (необязательно)')),
            const SizedBox(height: 11),
          ],
          TextField(controller: content, minLines: 7, maxLines: 15,
            decoration: const InputDecoration(labelText: 'Содержимое',
              alignLabelWithHint: true, hintText: 'Вставь текст или выбери файл…')),
          const SizedBox(height: 12),
          const Text('Данные сохраняются локально и не передаются в Groq автоматически.',
            style: TextStyle(fontSize: 12, color: BaboonColors.muted)),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(width: double.infinity, height: 50,
            child: FilledButton(onPressed: busy ? null : _save,
              child: Text(busy ? 'Сохраняем…' : 'Добавить в базу')))),
      ])),
    );
  }
}

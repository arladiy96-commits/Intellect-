import 'package:flutter/material.dart';
import '../../core/baboon/baboon_core.dart';
import '../../ui/baboon_style.dart';
import '../agents/agents_screen.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.onChat, required this.onKnowledge,
    required this.onPhoto});
  final VoidCallback onChat;
  final VoidCallback onKnowledge;
  final VoidCallback onPhoto;
  @override State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolTile {
  const _ToolTile(this.icon, this.title, this.subtitle, this.color, this.group,
      this.onTap, {this.soon = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String group;
  final VoidCallback onTap;
  final bool soon;
}

class _ToolsScreenState extends State<ToolsScreen> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  String group = 'Все';
  @override void dispose() { search.dispose(); searchFocus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final tiles = <_ToolTile>[
      _ToolTile(Icons.calculate_outlined, 'Математика', 'Вычисления, уравнения',
        const Color(0xFF64DAD1), 'Обучение', widget.onChat),
      _ToolTile(Icons.spellcheck_rounded, 'Русский язык', 'Правила, орфография',
        const Color(0xFFF0857E), 'Обучение', () => baboonSoon(context, 'Русский язык',
          'Отдельный модуль проверки орфографии и правил будет добавлен позже.'), soon: true),
      _ToolTile(Icons.code_rounded, 'Программирование', 'Код, анализ, тесты',
        const Color(0xFF84AEC7), 'Работа', () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const _AgentPage()))),
      _ToolTile(Icons.center_focus_strong_rounded, 'Анализ фото', 'OCR, документы',
        const Color(0xFF8D8BFF), 'Медиа', widget.onPhoto, soon: true),
      _ToolTile(Icons.folder_copy_outlined, 'База знаний', 'Учебники, книги, документы',
        BaboonColors.gold, 'Работа', widget.onKnowledge),
      _ToolTile(Icons.public, 'Интернет', 'Поиск и проверка фактов',
        const Color(0xFF6EBCE3), 'Работа', () => baboonSoon(context, 'Интернет',
          'Самостоятельный поиск с источниками подключим позднее.'), soon: true),
      _ToolTile(Icons.mic_outlined, 'Голос', 'Распознавание и озвучивание',
        const Color(0xFF6AB9EF), 'Медиа', () => baboonSoon(context, 'Голос',
          'Модуль диктовки и озвучивания ещё не подключён.'), soon: true),
      _ToolTile(Icons.android_outlined, 'Android', 'Действия на телефоне',
        const Color(0xFF79C791), 'Система', () => baboonSoon(context, 'Управление Android',
          'Потребуются отдельный модуль и явные разрешения на действия.'), soon: true),
      _ToolTile(Icons.extension_outlined, 'Свои инструменты', 'Расширение Бабуина',
        const Color(0xFFC5D5E4), 'Система', () => baboonSoon(context, 'Свои инструменты',
          'Реестр инструментов уже существует. Добавление своих модулей через интерфейс — следующий этап.'), soon: true),
    ];
    final filtered = tiles.where((item) => (group == 'Все' || group == item.group)
      && ('${item.title} ${item.subtitle}'.toLowerCase()
        .contains(search.text.toLowerCase()))).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
      Row(children: [
        const Expanded(child: BaboonTitle('Инструменты')),
        IconButton(icon: const Icon(Icons.search), tooltip: 'Поиск инструментов',
          onPressed: () => searchFocus.requestFocus()),
        IconButton(icon: const Icon(Icons.menu), tooltip: 'Меню приложения',
          onPressed: () => Scaffold.maybeOf(context)?.openDrawer()),
      ]),
      const SizedBox(height: 10),
      TextField(controller: search, focusNode: searchFocus, onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          isDense: true, prefixIcon: Icon(Icons.search, size: 20),
          hintText: 'Поиск инструментов...')),
      const SizedBox(height: 13),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final tag in const ['Все', 'Обучение', 'Работа', 'Медиа', 'Система']) ...[
          ChoiceChip(label: Text(tag), selected: group == tag,
            onSelected: (_) => setState(() => group = tag)),
          const SizedBox(width: 7),
        ],
      ])),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final tile in filtered)
            SizedBox(width: width, child: BaboonFeatureTile(
              icon: tile.icon, title: tile.title, subtitle: tile.subtitle,
              color: tile.color, onTap: tile.onTap, soon: tile.soon)),
        ]);
      }),
      const SizedBox(height: 16),
      BaboonPanel(onTap: () => baboonSoon(context, 'Пользовательские инструменты',
        'В ядре зарегистрировано ${BaboonCore.instance.tools.ids.length} инструмента. '
        'Графический редактор модулей добавим позже.'),
        child: const Row(children: [
          Icon(Icons.extension_outlined, color: BaboonColors.muted),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Пользовательские инструменты', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Добавляй свои модули', style: TextStyle(fontSize: 11, color: BaboonColors.muted)),
          ])),
          Icon(Icons.chevron_right, color: BaboonColors.muted),
        ])),
    ]);
  }
}

class _AgentPage extends StatelessWidget {
  const _AgentPage();
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Агенты · программирование')),
    body: const AgentsScreen(),
  );
}

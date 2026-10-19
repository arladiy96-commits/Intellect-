import 'package:flutter/material.dart';
import '../../core/knowledge/knowledge_repository.dart';
import '../../ui/baboon_style.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onChat, required this.onTools,
    required this.onKnowledge, required this.onSettings, required this.onModels,
    required this.onPhoto});
  final VoidCallback onChat;
  final VoidCallback onTools;
  final VoidCallback onKnowledge;
  final VoidCallback onSettings;
  final VoidCallback onModels;
  final VoidCallback onPhoto;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final knowledge = KnowledgeRepository.instance;
  @override
  void initState() {
    super.initState();
    knowledge.addListener(_refresh);
    knowledge.ensureLoaded().catchError((Object _) {});
  }
  void _refresh() { if (mounted) { setState(() {}); } }
  @override
  void dispose() {
    knowledge.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docs = knowledge.documents.length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
      Row(children: [
        const BaboonAvatar(radius: 19),
        const SizedBox(width: 10),
        const Text('БАБУИН', style: TextStyle(
          color: BaboonColors.gold, fontSize: 23, fontWeight: FontWeight.w800)),
        const Spacer(),
        IconButton(tooltip: 'Настройки', icon: const Icon(Icons.settings_outlined),
          onPressed: widget.onSettings),
      ]),
      const SizedBox(height: 10),
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.asset('assets/images/baboon_hero.jpg',
            height: 218, width: double.infinity, fit: BoxFit.cover,
            alignment: Alignment.topCenter),
        ),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          gradient: LinearGradient(begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, BaboonColors.background.withValues(alpha: .55), BaboonColors.background],
            stops: const [0, .52, 1]),
        ))),
        Positioned(left: 12, right: 12, bottom: 12,
          child: BaboonPanel(onTap: widget.onChat, padding: const EdgeInsets.all(13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Чем помочь?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 3),
              const Text('Спроси, загрузи файл, диктуй или выбери инструмент',
                style: TextStyle(color: BaboonColors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end,
                children: const [Text('Открыть чат', style: TextStyle(fontSize: 11, color: BaboonColors.gold)),
                  Icon(Icons.chevron_right, color: BaboonColors.gold, size: 18)]),
            ]))),
      ]),
      const SizedBox(height: 11),
      BaboonPanel(onTap: widget.onChat, padding: const EdgeInsets.all(12),
        child: Row(children: [
          const _AccentIcon(icon: Icons.history_rounded, color: BaboonColors.goldDark),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Продолжить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            Text('Последний диалог · открыть историю',
              style: TextStyle(fontSize: 11, color: BaboonColors.muted)),
          ])),
          const Icon(Icons.chevron_right, color: BaboonColors.muted),
        ])),
      const SizedBox(height: 11),
      LayoutBuilder(builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: tileWidth, child: BaboonFeatureTile(
            icon: Icons.book_outlined, color: BaboonColors.gold,
            title: 'База знаний', subtitle: '$docs документов', onTap: widget.onKnowledge)),
          SizedBox(width: tileWidth, child: BaboonFeatureTile(
            icon: Icons.photo_camera_outlined, color: const Color(0xFF7BB9FF),
            title: 'Анализ фото', subtitle: 'OCR · Документы',
            onTap: widget.onPhoto, soon: true)),
          SizedBox(width: tileWidth, child: BaboonFeatureTile(
            icon: Icons.calculate_outlined, color: const Color(0xFF62D7CD),
            title: 'Математика', subtitle: 'Вычисления', onTap: widget.onTools)),
          SizedBox(width: tileWidth, child: BaboonFeatureTile(
            icon: Icons.code_rounded, color: const Color(0xFF9697FB),
            title: 'Программирование', subtitle: 'Код · Проекты', onTap: widget.onTools)),
        ]);
      }),
      const SizedBox(height: 18),
      InkWell(onTap: widget.onModels,
        child: Row(children: const [
          Icon(Icons.hub_outlined, color: BaboonColors.gold, size: 17),
          SizedBox(width: 8),
          Expanded(child: Text('Модели и параметры', style: TextStyle(fontSize: 13, color: BaboonColors.muted))),
          Icon(Icons.chevron_right, color: BaboonColors.muted, size: 17),
        ])),
    ]);
  }
}

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 39, height: 39,
    decoration: BoxDecoration(color: color.withValues(alpha: .17),
      borderRadius: BorderRadius.circular(9)),
    child: Icon(icon, color: color),
  );
}

import 'package:flutter/material.dart';
import '../../ui/baboon_style.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../models/models_hub_screen.dart';
import '../settings/updates_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onChat, required this.onSettings});
  final VoidCallback onChat;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мой профиль')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      BaboonPanel(child: Row(children: [
        const BaboonAvatar(radius: 32),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('БАБУИН', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          Text('Умный помощник', style: TextStyle(color: BaboonColors.muted)),
        ])),
      ])),
      const SizedBox(height: 14),
      _row(context, Icons.psychology_outlined, 'Память', 'Воспоминания и важная информация',
        () => _push(context, const MemoryScreen())),
      _row(context, Icons.history_outlined, 'История чатов', 'Сохранённые диалоги', () {
        Navigator.pop(context); onChat();
      }),
      _row(context, Icons.bookmarks_outlined, 'Сохранённые решения',
        'В общей истории чатов', () { Navigator.pop(context); onChat(); }),
      _row(context, Icons.folder_outlined, 'Мои файлы', 'Знания и документы',
        () => _push(context, Scaffold(
          appBar: AppBar(title: const Text('База знаний')),
          body: const KnowledgeScreen()))),
      _row(context, Icons.memory_outlined, 'Модели и параметры',
        'Локальные и облачные модели', () => _push(context, const ModelsHubScreen())),
      _row(context, Icons.settings_outlined, 'Настройки приложения', 'Интерфейс и функции', () {
        Navigator.pop(context); onSettings();
      }),
      _row(context, Icons.sync_outlined, 'Синхронизация',
        'Подключение других устройств появится позже',
        () => baboonSoon(context, 'Синхронизация', 'Baboon API для других устройств подключим позже.')),
      _row(context, Icons.system_update_outlined, 'Обновления', 'GitHub Releases',
        () => _push(context, const UpdatesScreen())),
      const SizedBox(height: 12),
      const Center(child: Text('БАБУИН · Версия приложения',
        style: TextStyle(color: BaboonColors.muted, fontSize: 12))),
    ]),
  );

  static void _push(BuildContext context, Widget screen) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => screen));

  Widget _row(BuildContext context, IconData icon, String title, String subtitle,
    VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: BaboonPanel(padding: const EdgeInsets.all(11), onTap: onTap,
        child: Row(children: [
          Icon(icon, size: 20, color: BaboonColors.text),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: BaboonColors.muted, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right, color: BaboonColors.muted, size: 18),
        ])),
    );
}

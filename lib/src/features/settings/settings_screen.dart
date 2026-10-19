import 'package:flutter/material.dart';
import '../../ui/baboon_style.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../models/models_hub_screen.dart';
import '../profile/profile_screen.dart';
import 'cloud_settings_screen.dart';
import 'updates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.onChat, this.onOpenSettings});
  final VoidCallback? onChat;
  final VoidCallback? onOpenSettings;

  void _push(BuildContext context, Widget screen) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => screen));

  Widget _item(BuildContext context, IconData icon, String title,
    String subtitle, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: BaboonPanel(onTap: action, child: Row(children: [
        Icon(icon, color: BaboonColors.gold, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(subtitle, style: const TextStyle(color: BaboonColors.muted, fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right, color: BaboonColors.muted),
      ])),
    );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 28), children: [
      Row(children: [
        const Expanded(child: BaboonTitle('Настройки')),
        IconButton(onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Меню приложения', icon: const Icon(Icons.menu)),
      ]),
      const SizedBox(height: 13),
      _item(context, Icons.person_outline, 'Мой профиль',
        'Память, история и личные файлы',
        () => _push(context, ProfileScreen(onChat: onChat ?? () {},
          onSettings: onOpenSettings ?? () {}))),
      _item(context, Icons.hub_outlined, 'Модели и параметры',
        'Авто · Локальные · Облачные',
        () => _push(context, const ModelsHubScreen())),
      _item(context, Icons.cloud_outlined, 'Облачный ИИ',
        'Groq, OpenRouter, ключи, лимиты и токены',
        () => _push(context, const CloudSettingsScreen())),
      _item(context, Icons.psychology_outlined, 'Память Бабуина',
        'Воспоминания, категории, поиск',
        () => _push(context, const MemoryScreen())),
      _item(context, Icons.library_books_outlined, 'База знаний',
        'Коллекции и документы',
        () => _push(context, Scaffold(
          appBar: AppBar(title: Text('База знаний')), body: KnowledgeScreen()))),
      _item(context, Icons.security_outlined, 'Разрешения агентов',
        'Будет доступно после подключения действий Android',
        () => baboonSoon(context, 'Разрешения',
          'Сначала подключим рабочие агенты и запросы разрешений на конкретные действия.')),
      _item(context, Icons.tune_outlined, 'Настройки генерации',
        'Параметры зависят от выбранной модели',
        () => _push(context, const ModelsHubScreen())),
      _item(context, Icons.history_toggle_off_outlined, 'История действий',
        'Журнал автоматизаций появится позднее',
        () => baboonSoon(context, 'История действий',
          'Журнал инструментов и агентов добавим после подключения исполнительного ядра.')),
      _item(context, Icons.system_update_alt, 'Обновления',
        'Проверить и установить GitHub Release',
        () => _push(context, const UpdatesScreen())),
      const SizedBox(height: 13),
      const Center(child: Text('БАБУИН', style: TextStyle(
        color: BaboonColors.gold, letterSpacing: 2))),
    ]);
}

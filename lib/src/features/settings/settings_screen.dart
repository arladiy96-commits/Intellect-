import 'package:flutter/material.dart';

import 'cloud_settings_screen.dart';
import 'updates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Настройки', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Облачный ИИ · Groq / OpenRouter'),
            subtitle: const Text('API-ключ, модель и переключение облако / локально'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('Обновления'),
            subtitle: const Text('Проверить и установить APK из GitHub Releases'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UpdatesScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Разрешения агентов'),
            subtitle: Text('Добавим перед включением управления Android'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Настройки генерации'),
            subtitle: Text('Контекст, температура, производительность'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.history),
            title: Text('История действий'),
            subtitle: Text('Здесь появится журнал работы агентов'),
          ),
        ),
        const SizedBox(height: 20),
        const Center(child: Text('БАБУИН')),
      ],
    );
  }
}

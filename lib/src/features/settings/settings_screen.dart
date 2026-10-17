import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Настройки', style: Theme.of(context).textTheme.headlineSmall),
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
        const Center(child: Text('МОЙ ИИ · первоначальный каркас 0.1')),
      ],
    );
  }
}

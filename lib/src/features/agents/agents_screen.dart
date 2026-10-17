import 'package:flutter/material.dart';

class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const agents = [
      (Icons.code, 'Программист', 'Код, проекты и проверка решений'),
      (Icons.travel_explore, 'Исследователь', 'Поиск и анализ информации'),
      (Icons.description_outlined, 'Документы', 'Работа с файлами и данными'),
      (
        Icons.smartphone,
        'Android-агент',
        'Экран, приложения и разрешённые действия',
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('ИИ-агенты', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Заготовки. Исполнение задач и разрешения добавим далее.'),
        const SizedBox(height: 12),
        for (final agent in agents)
          Card(
            child: ListTile(
              leading: Icon(agent.$1),
              title: Text(agent.$2),
              subtitle: Text(agent.$3),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
          ),
      ],
    );
  }
}

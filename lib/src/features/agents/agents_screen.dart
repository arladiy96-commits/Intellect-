import 'package:flutter/material.dart';

import '../../core/baboon/baboon_core.dart';
import '../knowledge/knowledge_screen.dart';

class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const agents = [
      (Icons.code, 'Программист', 'Код, проекты и проверка решений'),
      (Icons.travel_explore, 'Исследователь', 'Поиск и анализ информации'),
      (Icons.description_outlined, 'Документы', 'Работа с файлами и данными'),
      (Icons.smartphone, 'Android-агент', 'Экран, приложения и разрешённые действия'),
    ];
    final core = BaboonCore.instance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Бабуин · инструменты и агенты',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.hub_outlined),
              const SizedBox(width: 10),
              Text('Baboon Core', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text('Рабочих инструментов: ${core.tools.ids.length}'),
            const SizedBox(height: 8),
            const Text('✓ Математика — вычисления и проверка'),
            const Text('✓ База знаний — локальный поиск по документам'),
            const SizedBox(height: 10),
            const Text('Попробуй в чате: «x + 35 = 82» или «найди в базе уравнение». '
                'Оба инструмента работают без запуска нейросети.'),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const KnowledgeScreen())),
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('Открыть базу знаний'),
            )),
          ]),
        )),
        const SizedBox(height: 16),
        Text('Будущие агенты', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Исполнение многошаговых задач и разрешения добавим следующим этапом.'),
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

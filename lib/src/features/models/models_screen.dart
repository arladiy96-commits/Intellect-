import 'package:flutter/material.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Модели', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Каталог для будущего локального движка. Здесь пока нет запущенной модели.',
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.memory),
            title: Text('Qwen3.5 4B · Q4_K_M'),
            subtitle: Text('Основная модель · подключение впереди'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.bolt_outlined),
            title: Text('Qwen3 1.7B'),
            subtitle: Text('Быстрая модель · подключение впереди'),
          ),
        ),
      ],
    );
  }
}

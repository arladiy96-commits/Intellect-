import 'package:flutter/material.dart';
import '../../core/ai/llama_native_engine.dart';
import '../../ui/baboon_style.dart';
import 'models_screen.dart';
import '../settings/cloud_settings_screen.dart';

class ModelsHubScreen extends StatelessWidget {
  const ModelsHubScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Модели и параметры'),
        bottom: const TabBar(
          labelColor: BaboonColors.gold,
          unselectedLabelColor: BaboonColors.muted,
          indicatorColor: BaboonColors.gold,
          tabs: [Tab(text: 'Авто'), Tab(text: 'Локальные'), Tab(text: 'Облачные')],
        ),
      ),
      body: const TabBarView(children: [
        _AutoOverview(), ModelsScreen(), _CloudOverview(),
      ]),
    ),
  );
}

class _AutoOverview extends StatelessWidget {
  const _AutoOverview();
  @override
  Widget build(BuildContext context) {
    final ai = LlamaNativeEngine.instance;
    return AnimatedBuilder(animation: ai, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16), children: [
        const BaboonPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Управление моделями', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          SizedBox(height: 5),
          Text('Автоматический подбор по типу задачи — следующий этап. '
            'Сейчас работает ручное переключение, как и раньше.',
            style: TextStyle(color: BaboonColors.muted)),
        ])),
        const SizedBox(height: 15),
        BaboonPanel(child: Row(children: [
          Icon(ai.cloudEnabled ? Icons.cloud_outlined : Icons.memory_outlined,
            color: BaboonColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Текущий исполнитель', style: TextStyle(color: BaboonColors.muted)),
            Text(ai.cloudEnabled ? '${ai.cloudProviderTitle} · ${ai.cloudModel}' : 'Локальная Qwen',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ])),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen())),
          icon: const Icon(Icons.tune_outlined),
          label: const Text('Настроить облачные модели'),
        ),
        const SizedBox(height: 14),
        const Text('Локальные GGUF и Vulkan/CPU настраиваются во вкладке «Локальные».',
          style: TextStyle(color: BaboonColors.muted)),
      ]));
  }
}

class _CloudOverview extends StatelessWidget {
  const _CloudOverview();
  @override Widget build(BuildContext context) {
    final ai = LlamaNativeEngine.instance;
    return AnimatedBuilder(animation: ai, builder: (context, child) => ListView(
      padding: const EdgeInsets.all(16), children: [
        for (final spec in const [
          (Icons.bolt, 'Groq', 'GPT-OSS 120B · GPT-OSS 20B'),
          (Icons.cloud_outlined, 'OpenRouter', 'Другие облачные модели'),
        ]) ...[
          BaboonPanel(onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen())),
            child: Row(children: [
              Icon(spec.$1, color: BaboonColors.gold, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.$2, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(spec.$3, style: const TextStyle(fontSize: 11, color: BaboonColors.muted)),
              ])),
              const Icon(Icons.chevron_right, color: BaboonColors.muted),
            ])),
          const SizedBox(height: 11),
        ],
        Text(ai.cloudEnabled ? 'Сейчас выбрано: ${ai.cloudProviderTitle} · ${ai.cloudModel}'
          : 'Сейчас выбран локальный режим', style: const TextStyle(color: BaboonColors.muted)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen())),
          icon: const Icon(Icons.key_outlined), label: const Text('Ключи и выбор модели')),
      ]));
  }
}

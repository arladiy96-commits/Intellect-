import 'package:flutter/material.dart';
import '../../core/ai/llama_native_engine.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  String _size(int bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';

  @override
  Widget build(BuildContext context) {
    final ai = LlamaNativeEngine.instance;
    return AnimatedBuilder(
      animation: ai,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Локальные модели', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('GGUF запускается непосредственно в приложении, без Termux и интернета.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ai.isBusy || ai.isGenerating ? null : ai.importModel,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Добавить GGUF с телефона'),
          ),
          if (ai.importProgress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: ai.importProgress),
          ],
          const SizedBox(height: 12),
          Text(ai.status, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (ai.models.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Моделей пока нет. Добавь Qwen3.5 4B Q4_K_M или Qwen3 1.7B (GGUF).'),
            )),
          for (final model in ai.models)
            Card(
              child: ListTile(
                leading: Icon(ai.activeModelPath == model.path
                    ? Icons.check_circle : Icons.memory),
                title: Text(model.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_size(model.bytes)} · ${ai.activeModelPath == model.path ? 'запущена' : 'не запущена'}'),
                trailing: ai.activeModelPath == model.path
                    ? OutlinedButton(
                        onPressed: ai.isBusy || ai.isGenerating ? null : ai.unloadModel,
                        child: const Text('Стоп'),
                      )
                    : FilledButton.tonal(
                        onPressed: ai.isBusy || ai.isGenerating ? null : () async {
                          try {
                            await ai.loadModel(model.path);
                          } catch (_) { /* Status is shown by the engine. */ }
                        },
                        child: const Text('Запустить'),
                      ),
              ),
            ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Производительность CPU',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Проверь 1, 2 и 4 потока: на некоторых CPU больше потоков '
                      'означает меньшую скорость. Модель нужно перезапускать.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final threads in [1, 2, 4, 6, 8])
                        ChoiceChip(
                          label: Text('$threads ${threads == 1 ? 'поток' : (threads == 2 || threads == 4) ? 'потока' : 'потоков'}'),
                          selected: ai.cpuThreads == threads,
                          onSelected: ai.isBusy || ai.isGenerating || ai.isModelLoaded
                              ? null
                              : (selected) async {
                                  if (!selected) return;
                                  try {
                                    await ai.setCpuThreads(threads);
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$error')),
                                      );
                                    }
                                  }
                                },
                        ),
                    ],
                  ),
                  if (ai.isModelLoaded)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Для смены потоков нажми «Стоп» у модели.'),
                    ),
                  if (ai.lastPerformance != null) ...[
                    const Divider(height: 24),
                    Text('Последний ответ',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Скорость: '
                        '${ai.lastPerformance!.tokensPerSecond.toStringAsFixed(1)} токена/с'),
                    Text('Подготовка запроса: '
                        '${(ai.lastPerformance!.prefillMs / 1000).toStringAsFixed(1)} с'),
                    Text('Весь ответ: '
                        '${(ai.lastPerformance!.totalMs / 1000).toStringAsFixed(1)} с'),
                    Text('Сгенерировано: ${ai.lastPerformance!.generatedTokens} токенов'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Важно: GGUF в приватной папке Termux здесь не виден. Сначала скопируй файл в «Загрузки». При импорте приложение создаст собственную копию модели.'),
        ],
      ),
    );
  }
}

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
          const SizedBox(height: 16),
          const Text('Важно: GGUF в приватной папке Termux здесь не виден. Сначала скопируй файл в «Загрузки». При импорте приложение создаст собственную копию модели.'),
        ],
      ),
    );
  }
}

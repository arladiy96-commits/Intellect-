import 'package:flutter/material.dart';

import '../../core/ai/cloud_ai_engine.dart';
import '../../core/ai/llama_native_engine.dart';

class CloudSettingsScreen extends StatefulWidget {
  const CloudSettingsScreen({super.key});

  @override
  State<CloudSettingsScreen> createState() => _CloudSettingsScreenState();
}

class _CloudSettingsScreenState extends State<CloudSettingsScreen> {
  final _ai = LlamaNativeEngine.instance;
  final _key = TextEditingController();
  final _openRouterModel = TextEditingController();
  bool _working = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ai.addListener(_refresh);
    _openRouterModel.text = CloudCredentials.instance.openRouterModel;
    _initialize();
  }

  Future<void> _initialize() async {
    await _ai.refreshCloud();
    if (mounted) {
      _openRouterModel.text = CloudCredentials.instance.openRouterModel;
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ai.removeListener(_refresh);
    _key.dispose();
    _openRouterModel.dispose();
    super.dispose();
  }

  void _info(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working || _ai.isBusy || _ai.isGenerating) return;
    setState(() => _working = true);
    try {
      await operation();
    } catch (error) {
      _info('$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _choose(CloudProvider provider) => _run(() async {
    await _ai.selectCloudProvider(provider);
    _key.clear();
    _openRouterModel.text = CloudCredentials.instance.openRouterModel;
  });

  Future<void> _removeKey() async {
    final provider = _ai.cloudProvider;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить ключ ${provider.title}?'),
        content: const Text('Ключ удалится только с телефона. История чатов, '
            'воспоминания и локальные модели сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        await _ai.deleteCloudKey();
        _key.clear();
        _info('Ключ удалён');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _working || _ai.isGenerating || _ai.isBusy;
    final provider = _ai.cloudProvider;
    final isGroq = provider == CloudProvider.groq;
    final hasKey = _ai.cloudHasKey;
    final credentials = CloudCredentials.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Облачный ИИ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Выбор провайдера', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(
              label: const Text('Groq · основной'),
              selected: isGroq,
              onSelected: disabled ? null : (selected) {
                if (selected) _choose(CloudProvider.groq);
              },
            ),
            ChoiceChip(
              label: const Text('OpenRouter · резервный'),
              selected: !isGroq,
              onSelected: disabled ? null : (selected) {
                if (selected) _choose(CloudProvider.openrouter);
              },
            ),
          ]),
          const SizedBox(height: 10),
          Text(isGroq
              ? 'Groq выполняет вычисления в облаке. Доступны GPT-OSS 120B, '
                  'GPT-OSS 20B и Qwen 3.8 27B (Preview).'
              : 'OpenRouter предоставляет доступ к разным моделям. '
                  'По умолчанию используется бесплатный маршрутизатор.'),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('API-ключ ${provider.title}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(hasKey ? 'Ключ сохранён на этом устройстве.'
                  : 'Ключ ещё не сохранён.'),
              const SizedBox(height: 10),
              TextField(
                controller: _key,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Вставь API-ключ',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Показать ключ' : 'Скрыть ключ',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: disabled ? null : () => _run(() async {
                  await _ai.saveCloudKey(_key.text);
                  _key.clear();
                  _info('Ключ ${provider.title} сохранён');
                }),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Сохранить ключ'),
              ),
              if (hasKey)
                TextButton.icon(
                  onPressed: disabled ? null : _removeKey,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить ключ'),
                ),
              const SizedBox(height: 6),
              SelectableText('Получить ключ: ${provider.keyUrl}'),
              const SizedBox(height: 6),
              const Text('Никому не отправляй API-ключ, не помещай его в GitHub. '
                  'Для платных моделей установи лимит расходов у провайдера.'),
            ]),
          )),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Модель', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (isGroq) ...[
                for (final entry in groqModels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_ai.cloudModel == entry.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(entry.value),
                      subtitle: Text(entry.key),
                      onTap: disabled ? null : () => _run(() async {
                        await _ai.saveCloudModel(entry.key);
                        _info('Выбрана ${entry.value}');
                      }),
                    ),
                  ),
                const Text('GPT-OSS 120B — более мощная, 20B — быстрее. '
                    'Qwen 27B пока предварительная (Preview).'),
              ] else ...[
                const Text('openrouter/free выбирает одну из доступных '
                    'бесплатных моделей. Другие ID могут быть платными.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _openRouterModel,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'ID модели OpenRouter',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: disabled ? null : () =>
                      _openRouterModel.text = CloudCredentials.defaultOpenRouterModel,
                  child: const Text('Бесплатная модель по умолчанию'),
                ),
                FilledButton.tonal(
                  onPressed: disabled ? null : () => _run(() async {
                    await _ai.saveCloudModel(_openRouterModel.text);
                    _info('Модель сохранена');
                  }),
                  child: const Text('Сохранить ID модели'),
                ),
              ],
            ]),
          )),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Режим чата', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text('Локально'),
                  selected: !_ai.cloudEnabled,
                  onSelected: disabled ? null : (value) {
                    if (value) _run(() => _ai.setCloudMode(false));
                  },
                ),
                ChoiceChip(
                  label: Text('Облако · ${provider.title}'),
                  selected: _ai.cloudEnabled,
                  onSelected: disabled || !hasKey ? null : (value) {
                    if (value) _run(() => _ai.setCloudMode(true));
                  },
                ),
              ]),
              const SizedBox(height: 8),
              const Text('В режиме облака локальная Qwen выгружается из RAM. '
                  'Включение резервного провайдера всегда ручное.'),
            ]),
          )),
          if (isGroq && _ai.cloudRemainingRequests != null) ...[
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Доступная квота (последний ответ)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Запросов за день: ${_ai.cloudRemainingRequests}'),
                if (_ai.cloudRemainingTokens != null)
                  Text('Токенов в минуту: ${_ai.cloudRemainingTokens}'),
                const Text('Показатели приходят от Groq после запроса и '
                    'могут измениться. Дневные лимиты зависят от аккаунта.'),
              ]),
            )),
          ],
          const SizedBox(height: 12),
          const Text('Конфиденциальность: при обращении к облаку выбранному '
              'провайдеру и его поставщику модели отправляются вопрос, '
              'необходимая история чата и подобранные записи памяти. '
              'Без интернета работает только локальная Qwen.'),
          const SizedBox(height: 12),
          Text('Ключи: Groq ${credentials.hasGroqKey ? 'сохранён' : 'не задан'} · '
              'OpenRouter ${credentials.hasOpenRouterKey ? 'сохранён' : 'не задан'}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

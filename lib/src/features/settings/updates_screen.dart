import 'package:flutter/material.dart';
import '../../core/updates/baboon_update_service.dart';

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final _service = BaboonUpdateService();
  UpdateRelease? _release;
  bool _checking = false;
  bool _downloading = false;
  bool _downloaded = false;
  double _progress = 0;
  String _status = 'Проверяем обновления…';
  int? _installedBuild;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _status = 'Подключаемся к GitHub Releases…';
    });
    try {
      final installed = await _service.installedBuild();
      final update = await _service.checkAvailable();
      if (!mounted) return;
      setState(() {
        _installedBuild = installed;
        _release = update;
        _downloaded = false;
        _status = update == null
            ? 'Установлена последняя версия.'
            : 'Доступна новая версия ${update.tag}.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Не удалось проверить: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download() async {
    final release = _release;
    if (release == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Загружаем APK…';
    });
    try {
      await _service.download(release, onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      });
      if (!mounted) return;
      setState(() {
        _downloaded = true;
        _status = 'APK загружен. Можно установить обновление.';
      });
      await _install();
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final release = _release;
    if (release == null || !_downloaded) return;
    try {
      final state = await _service.install(release);
      if (!mounted) return;
      setState(() => _status = state == 'permission_required'
          ? 'Разреши установку из Бабуина в настройках Android и нажми «Установить» ещё раз.'
          : 'Подтверди обновление в системном установщике Android.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка установки: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Обновления')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_alt, size: 54),
          const SizedBox(height: 16),
          Text('Обновления Бабуина', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (_installedBuild != null)
            Text('Текущая сборка: $_installedBuild'),
          const SizedBox(height: 8),
          Text(_status),
          if (_checking) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_release != null) ...[
            const SizedBox(height: 22),
            Text('Новая версия: ${_release!.tag}', style: theme.textTheme.titleMedium),
            if (_release!.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(_release!.releaseNotes),
            ],
            const SizedBox(height: 18),
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ] else if (!_downloaded)
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: const Text('Скачать и установить'),
              )
            else
              FilledButton.icon(
                onPressed: _install,
                icon: const Icon(Icons.install_mobile),
                label: const Text('Установить обновление'),
              ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _checking || _downloading ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('Проверить обновления'),
          ),
          const SizedBox(height: 20),
          Text(
            'Сборки берутся из публичных GitHub Releases. Установка поверх приложения '
            'возможна только при совпадающей подписи и большем номере сборки. '
            'Android всегда запросит подтверждение установки.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

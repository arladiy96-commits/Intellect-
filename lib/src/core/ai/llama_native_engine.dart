import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_engine.dart';
import 'cloud_ai_engine.dart';

class GenerationPerformance {
  const GenerationPerformance({
    required this.prefillMs,
    required this.tokensPerSecond,
    required this.totalMs,
    required this.generatedTokens,
  });
  final double prefillMs;
  final double tokensPerSecond;
  final double totalMs;
  final int generatedTokens;
}

class InstalledModel {
  const InstalledModel({required this.name, required this.path, required this.bytes});
  final String name;
  final String path;
  final int bytes;

  factory InstalledModel.fromMap(Map<dynamic, dynamic> map) => InstalledModel(
    name: map['name'] as String,
    path: map['path'] as String,
    bytes: (map['bytes'] as num).toInt(),
  );
}

/// Shared chat engine: local llama.cpp, Groq or OpenRouter.
/// GGUF, chat history and memory never need migrating when changing modes.
class LlamaNativeEngine extends ChangeNotifier implements AiEngine {
  LlamaNativeEngine._() {
    _subscription = const EventChannel('moy_ai/llama_events')
        .receiveBroadcastStream()
        .listen(_handleEvent, onError: (Object error) {
          status = 'Ошибка канала: $error';
          notifyListeners();
        });
    unawaited(refreshModels());
    unawaited(refreshCpuThreads());
    unawaited(refreshGpuSettings());
    unawaited(refreshCloud());
  }

  static final LlamaNativeEngine instance = LlamaNativeEngine._();
  static const _channel = MethodChannel('moy_ai/llama');
  final _tokens = StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  late final StreamSubscription<dynamic> _subscription;
  final _cloud = CloudAiEngine.instance;

  List<InstalledModel> models = [];
  String? activeModelPath;
  String status = 'Выбери GGUF в разделе «Модели»';
  double? importProgress;
  int cpuThreads = 4;
  int gpuLayers = 0;
  int appliedGpuLayers = 0;
  String? gpuDeviceName;
  String? gpuWarning;
  GenerationPerformance? lastPerformance;
  bool isBusy = false;
  bool isGenerating = false;

  bool cloudEnabled = false;
  bool cloudHasKey = false;
  String cloudModel = CloudCredentials.defaultGroqModel;
  CloudProvider cloudProvider = CloudProvider.groq;
  int? get cloudRemainingRequests => _cloud.remainingRequests;
  int? get cloudRemainingTokens => _cloud.remainingTokens;
  String get cloudProviderTitle => cloudProvider.title;
  bool get cloudGroqHasKey => _cloud.credentials.hasGroqKey;
  bool get cloudOpenRouterHasKey => _cloud.credentials.hasOpenRouterKey;
  bool get isLocalModelLoaded => activeModelPath != null;
  bool get isModelLoaded => cloudEnabled ? cloudHasKey : isLocalModelLoaded;

  void _handleEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<dynamic, dynamic>.from(raw);
    final type = event['type'];
    if (type == 'importProgress') {
      importProgress = (event['progress'] as num?)?.toDouble();
      status = 'Копирование модели: ${((importProgress ?? 0) * 100).round()}%';
      notifyListeners();
    } else if (type == 'performance') {
      lastPerformance = GenerationPerformance(
        prefillMs: (event['prefillMs'] as num? ?? 0).toDouble(),
        tokensPerSecond: (event['tokensPerSecond'] as num? ?? 0).toDouble(),
        totalMs: (event['totalMs'] as num? ?? 0).toDouble(),
        generatedTokens: (event['generatedTokens'] as num? ?? 0).toInt(),
      );
      notifyListeners();
    } else if (type == 'token' || type == 'done' || type == 'error') {
      _tokens.add(event);
    }
  }

  Future<void> refreshCloud() async {
    try {
      await _cloud.credentials.load();
      cloudEnabled = _cloud.credentials.enabled;
      cloudHasKey = _cloud.credentials.hasKey;
      cloudModel = _cloud.credentials.model;
      cloudProvider = _cloud.credentials.provider;
      if (cloudEnabled) status = 'Облако · ${cloudProvider.title} · $cloudModel';
      notifyListeners();
    } on Exception catch (_) {
      // If secure storage fails, remain offline. Do not expose key contents.
      cloudEnabled = false;
      cloudHasKey = false;
      notifyListeners();
    }
  }

  Future<void> saveCloudKey(String key) async {
    if (isBusy || isGenerating) throw StateError('Дождись завершения ответа');
    await _cloud.credentials.saveKey(_cloud.credentials.provider, key);
    await refreshCloud();
  }

  Future<void> deleteCloudKey() async {
    if (isBusy || isGenerating) throw StateError('Дождись завершения ответа');
    await _cloud.credentials.removeKey(_cloud.credentials.provider);
    await refreshCloud();
    status = isLocalModelLoaded ? 'Локальная модель готова' : 'Выбери GGUF в разделе «Модели»';
    notifyListeners();
  }

  Future<void> saveCloudModel(String model) async {
    if (isBusy || isGenerating) throw StateError('Дождись завершения ответа');
    await _cloud.credentials.saveModel(_cloud.credentials.provider, model);
    await refreshCloud();
  }

  Future<void> selectCloudProvider(CloudProvider provider) async {
    if (isBusy || isGenerating) throw StateError('Дождись завершения ответа');
    await _cloud.credentials.selectProvider(provider);
    _cloud.remainingRequests = null;
    _cloud.remainingTokens = null;
    await refreshCloud();
    status = cloudEnabled
        ? 'Облако · ${cloudProvider.title} · $cloudModel'
        : 'Выбери режим или сохрани ключ ${cloudProvider.title}';
    notifyListeners();
  }

  Future<void> setCloudMode(bool value) async {
    if (isBusy || isGenerating) throw StateError('Дождись завершения ответа');
    await _cloud.credentials.load();
    if (value && !_cloud.credentials.hasKey) {
      throw StateError('Сначала добавь API-ключ в настройках облачного ИИ');
    }
    if (value && isLocalModelLoaded) {
      // Free CPU/GPU/RAM before using remote inference.
      await unloadModel();
    }
    await _cloud.credentials.setEnabled(value);
    cloudEnabled = value;
    cloudHasKey = _cloud.credentials.hasKey;
    cloudModel = _cloud.credentials.model;
    lastPerformance = null;
    cloudProvider = _cloud.credentials.provider;
    status = value ? 'Облако · ${cloudProvider.title} · $cloudModel'
        : 'Локальный режим: запусти GGUF в разделе «Модели»';
    notifyListeners();
  }

  Future<void> refreshCpuThreads() async {
    try {
      cpuThreads = await _channel.invokeMethod<int>('getCpuThreads') ?? 4;
      notifyListeners();
    } on Exception catch (_) {
      // First-run fallback; no impact on inference or model import.
    }
  }

  Future<void> setCpuThreads(int threads) async {
    if (isBusy || isGenerating || isLocalModelLoaded) {
      throw StateError('Сначала выгрузи модель');
    }
    if (![1, 2, 4, 6, 8].contains(threads)) {
      throw ArgumentError.value(threads, 'threads');
    }
    await _channel.invokeMethod<void>('setCpuThreads', {'threads': threads});
    cpuThreads = threads;
    lastPerformance = null;
    status = 'Настроено $threads потоков. Теперь запусти модель.';
    notifyListeners();
  }

  Future<void> refreshGpuSettings() async {
    try {
      gpuLayers = await _channel.invokeMethod<int>('getGpuLayers') ?? 0;
      final recovered = await _channel.invokeMethod<bool>('getGpuRecovery') ?? false;
      if (recovered) {
        gpuWarning = 'Vulkan прервался при загрузке. Для безопасности возвращён CPU.';
      }
      notifyListeners();
    } on Exception catch (_) {
      // Remain on CPU when the native bridge does not expose GPU settings.
    }
  }

  Future<void> setGpuLayers(int layers) async {
    if (isBusy || isGenerating || isLocalModelLoaded) {
      throw StateError('Сначала выгрузи модель');
    }
    if (![0, 8, 16, 32, 99].contains(layers)) {
      throw ArgumentError.value(layers, 'layers');
    }
    await _channel.invokeMethod<void>('setGpuLayers', {'layers': layers});
    gpuLayers = layers;
    gpuWarning = null;
    lastPerformance = null;
    status = layers == 0
        ? 'Режим CPU. Теперь запусти модель.'
        : 'Выбрано $layers GPU-слоёв. Запусти модель для проверки Vulkan.';
    notifyListeners();
  }

  Future<void> refreshModels() async {
    try {
      final results = await _channel.invokeListMethod<dynamic>('listModels');
      models = (results ?? [])
          .whereType<Map>()
          .map(InstalledModel.fromMap)
          .toList();
      notifyListeners();
    } on Exception catch (e) {
      status = 'Модели недоступны: $e';
      notifyListeners();
    }
  }

  Future<void> importModel() async {
    if (isBusy || isGenerating) return;
    isBusy = true;
    importProgress = 0;
    status = 'Выбери файл модели .gguf';
    notifyListeners();
    try {
      final path = await _channel.invokeMethod<String>('importModel');
      await refreshModels();
      status = path == null
          ? 'Выбор файла отменён'
          : 'Модель импортирована. Нажми «Запустить».';
    } on PlatformException catch (e) {
      status = 'Ошибка импорта: ${e.message}';
    } finally {
      isBusy = false;
      importProgress = null;
      notifyListeners();
    }
  }

  @override
  Future<void> loadModel(String modelPath) async {
    if (isBusy || isGenerating) return;
    // Starting a local GGUF always selects local mode. Do not leave both
    // models resident while the cloud mode is selected.
    if (cloudEnabled) await setCloudMode(false);
    isBusy = true;
    status = 'Загрузка модели в оперативную память…';
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>(
        'loadModel', {'path': modelPath});
      activeModelPath = modelPath;
      appliedGpuLayers = (result?['gpuLayers'] as num?)?.toInt() ?? 0;
      gpuLayers = appliedGpuLayers;
      gpuDeviceName = result?['gpuName']?.toString();
      final fallback = result?['fallback']?.toString() ?? '';
      gpuWarning = fallback.isEmpty ? null
          : 'Vulkan не запустился: $fallback. Автоматически включён CPU.';
      lastPerformance = null;
      status = appliedGpuLayers > 0
          ? 'Vulkan GPU: $appliedGpuLayers слоёв ($cpuThreads CPU-потоков)'
          : 'CPU: $cpuThreads потоков${fallback.isEmpty ? '' : ' (GPU недоступен)'}';
    } on PlatformException catch (e) {
      activeModelPath = null;
      appliedGpuLayers = 0;
      status = 'Не удалось загрузить: ${e.message}';
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> unloadModel() async {
    if (isGenerating || isBusy) return;
    isBusy = true;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('unloadModel');
      activeModelPath = null;
      appliedGpuLayers = 0;
      status = 'Модель выгружена';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  Stream<String> streamReply(List<AiMessage> conversation) async* {
    if (!isModelLoaded) throw StateError('Сначала выбери модель');
    if (isGenerating || isBusy) throw StateError('Дождись завершения предыдущей операции');

    isGenerating = true;
    final useCloud = cloudEnabled;
    status = useCloud ? 'Облако · получаю ответ…' : 'Генерация ответа…';
    notifyListeners();
    if (useCloud) {
      try {
        yield* _cloud.streamReply(conversation);
        status = 'Облако · ${cloudProvider.title} · $cloudModel';
      } on Object catch (e) {
        status = 'Ошибка облачного ответа: $e';
        rethrow;
      } finally {
        isGenerating = false;
        notifyListeners();
      }
      return;
    }

    final stream = StreamController<String>();
    final subscription = _tokens.stream.listen((event) {
      switch (event['type']) {
        case 'token':
          if (!stream.isClosed) stream.add(event['text'] as String? ?? '');
        case 'done':
          if (!stream.isClosed) unawaited(stream.close());
        case 'error':
          if (!stream.isClosed) {
            stream.addError(StateError(event['message'] ?? 'Ошибка генерации'));
            unawaited(stream.close());
          }
      }
    });
    try {
      await _channel.invokeMethod<void>('generate', {
        'messages': conversation.map((m) => {'role': m.role, 'text': m.text}).toList(),
        'maxTokens': 512,
      });
      yield* stream.stream;
      status = 'Модель готова к работе';
    } on Object catch (e) {
      status = 'Ошибка генерации: $e';
      rethrow;
    } finally {
      await subscription.cancel();
      if (!stream.isClosed) await stream.close();
      isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!isGenerating) return;
    if (cloudEnabled) {
      await _cloud.stop();
    } else {
      await _channel.invokeMethod<void>('stop');
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_tokens.close());
    super.dispose();
  }
}

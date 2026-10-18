import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_engine.dart';

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

/// Device-only llama.cpp bridge. Does not use Termux, a local HTTP server,
/// or an external API. Android imports GGUF using ACTION_OPEN_DOCUMENT.
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
  }

  static final LlamaNativeEngine instance = LlamaNativeEngine._();
  static const _channel = MethodChannel('moy_ai/llama');
  final _tokens = StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  late final StreamSubscription<dynamic> _subscription;

  List<InstalledModel> models = [];
  String? activeModelPath;
  String status = 'Выбери GGUF в разделе «Модели»';
  double? importProgress;
  int cpuThreads = 4;
  GenerationPerformance? lastPerformance;
  bool isBusy = false;
  bool isGenerating = false;

  bool get isModelLoaded => activeModelPath != null;

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

  Future<void> refreshCpuThreads() async {
    try {
      cpuThreads = await _channel.invokeMethod<int>('getCpuThreads') ?? 4;
      notifyListeners();
    } on Exception catch (_) {
      // First-run fallback; no impact on inference or model import.
    }
  }

  Future<void> setCpuThreads(int threads) async {
    if (isBusy || isGenerating || isModelLoaded) {
      throw StateError('Сначала выгрузи модель');
    }
    if (![4, 6, 8].contains(threads)) {
      throw ArgumentError.value(threads, 'threads');
    }
    await _channel.invokeMethod<void>('setCpuThreads', {'threads': threads});
    cpuThreads = threads;
    lastPerformance = null;
    status = 'Настроено $threads потоков. Теперь запусти модель.';
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
    isBusy = true;
    status = 'Загрузка модели в оперативную память…';
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('loadModel', {'path': modelPath});
      activeModelPath = modelPath;
      lastPerformance = null;
      status = 'Модель готова к работе ($cpuThreads CPU-потоков)';
    } on PlatformException catch (e) {
      activeModelPath = null;
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
      status = 'Модель выгружена';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  Stream<String> streamReply(List<AiMessage> conversation) async* {
    if (!isModelLoaded) throw StateError('Сначала запусти модель');
    if (isGenerating || isBusy) throw StateError('Дождись завершения предыдущей операции');

    isGenerating = true;
    status = 'Генерация ответа…';
    notifyListeners();
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
    if (isGenerating) await _channel.invokeMethod<void>('stop');
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_tokens.close());
    super.dispose();
  }
}

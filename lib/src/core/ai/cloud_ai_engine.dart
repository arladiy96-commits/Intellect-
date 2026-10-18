import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

import 'ai_engine.dart';

enum CloudProvider { groq, openrouter }

extension CloudProviderInfo on CloudProvider {
  String get title => this == CloudProvider.groq ? 'Groq' : 'OpenRouter';
  String get keyUrl => this == CloudProvider.groq
      ? 'https://console.groq.com/keys'
      : 'https://openrouter.ai/settings/keys';
  Uri get endpoint => Uri.parse(this == CloudProvider.groq
      ? 'https://api.groq.com/openai/v1/chat/completions'
      : 'https://openrouter.ai/api/v1/chat/completions');
}

const groqModels = <String, String>{
  'openai/gpt-oss-120b': 'GPT-OSS 120B · основной',
  'openai/gpt-oss-20b': 'GPT-OSS 20B · быстрый',
  'qwen/qwen3.8-27b': 'Qwen 3.8 27B · Preview',
};

/// Every key stays on this Android device (Keystore-backed plugin).
/// No keys are shipped with the APK or stored in the public repository.
class CloudCredentials {
  CloudCredentials._();
  static final CloudCredentials instance = CloudCredentials._();
  static const storage = FlutterSecureStorage();
  static const defaultGroqModel = 'openai/gpt-oss-120b';
  static const defaultOpenRouterModel = 'openrouter/free';

  CloudProvider provider = CloudProvider.groq;
  String groqModel = defaultGroqModel;
  String openRouterModel = defaultOpenRouterModel;
  bool hasGroqKey = false;
  bool hasOpenRouterKey = false;
  bool enabled = false;
  Future<void>? _loading;

  String get model => provider == CloudProvider.groq ? groqModel : openRouterModel;
  bool get hasKey => hasKeyFor(provider);
  bool hasKeyFor(CloudProvider p) =>
      p == CloudProvider.groq ? hasGroqKey : hasOpenRouterKey;

  static String _keyName(CloudProvider p) =>
      p == CloudProvider.groq ? 'baboon_groq_key' : 'baboon_openrouter_key';
  static String _modelName(CloudProvider p) =>
      p == CloudProvider.groq ? 'baboon_groq_model' : 'baboon_openrouter_model';

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final values = await Future.wait([
        storage.read(key: 'baboon_groq_key'),
        storage.read(key: 'baboon_openrouter_key'),
        storage.read(key: 'baboon_cloud_provider'),
        storage.read(key: 'baboon_groq_model'),
        storage.read(key: 'baboon_openrouter_model'),
        storage.read(key: 'baboon_cloud_selected'),
      ]);
      hasGroqKey = (values[0] ?? '').trim().isNotEmpty;
      hasOpenRouterKey = (values[1] ?? '').trim().isNotEmpty;
      provider = values[2] == 'openrouter' ? CloudProvider.openrouter : CloudProvider.groq;
      groqModel = groqModels.containsKey(values[3]) ? values[3]! : defaultGroqModel;
      final openRouter = (values[4] ?? '').trim();
      openRouterModel = openRouter.isEmpty ? defaultOpenRouterModel : openRouter;
      enabled = values[5] == 'true' && hasKey;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<String?> readKey(CloudProvider p) async {
    await load();
    return storage.read(key: _keyName(p));
  }

  Future<void> saveKey(CloudProvider p, String key) async {
    await load();
    final value = key.trim();
    if (value.isEmpty) throw ArgumentError('Введи API-ключ ${p.title}');
    await storage.write(key: _keyName(p), value: value);
    if (p == CloudProvider.groq) {
      hasGroqKey = true;
    } else {
      hasOpenRouterKey = true;
    }
  }

  Future<void> removeKey(CloudProvider p) async {
    await load();
    await storage.delete(key: _keyName(p));
    if (p == CloudProvider.groq) {
      hasGroqKey = false;
    } else {
      hasOpenRouterKey = false;
    }
    if (provider == p) await setEnabled(false);
  }

  Future<void> selectProvider(CloudProvider p) async {
    await load();
    await storage.write(key: 'baboon_cloud_provider', value: p.name);
    provider = p;
    if (!hasKey) await setEnabled(false);
  }

  Future<void> saveModel(CloudProvider p, String value) async {
    await load();
    final id = value.trim();
    if (id.isEmpty || id.length > 180 || RegExp(r'\s').hasMatch(id)) {
      throw ArgumentError('Некорректный ID модели');
    }
    if (p == CloudProvider.groq && !groqModels.containsKey(id)) {
      throw ArgumentError('Выбери одну из доступных моделей Groq');
    }
    await storage.write(key: _modelName(p), value: id);
    if (p == CloudProvider.groq) {
      groqModel = id;
    } else {
      openRouterModel = id;
    }
  }

  Future<void> setEnabled(bool value) async {
    await load();
    if (value && !hasKey) throw StateError('Сначала сохрани API-ключ ${provider.title}');
    await storage.write(key: 'baboon_cloud_selected', value: '$value');
    enabled = value;
  }
}

/// The API's actual token usage, including history and any model-side reasoning.
/// These numbers come from the streamed `usage` chunk, not text-length guesses.
class CloudTokenUsage {
  const CloudTokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.model,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final String model;

  static CloudTokenUsage? fromChunk(Map<dynamic, dynamic> chunk) {
    final raw = chunk['usage'];
    if (raw is! Map) return null;
    final prompt = (raw['prompt_tokens'] as num?)?.toInt();
    final completion = (raw['completion_tokens'] as num?)?.toInt();
    final total = (raw['total_tokens'] as num?)?.toInt();
    if (prompt == null || completion == null || prompt < 0 || completion < 0) {
      return null;
    }
    return CloudTokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total ?? prompt + completion,
      model: chunk['model']?.toString() ?? '',
    );
  }

  Map<String, Object> toJson() => {
    'prompt': promptTokens,
    'completion': completionTokens,
    'total': totalTokens,
    'model': model,
  };

  static CloudTokenUsage? fromJson(Object? value) {
    if (value is! Map) return null;
    final prompt = (value['prompt'] as num?)?.toInt();
    final completion = (value['completion'] as num?)?.toInt();
    if (prompt == null || completion == null) return null;
    return CloudTokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: (value['total'] as num?)?.toInt() ?? prompt + completion,
      model: value['model']?.toString() ?? '',
    );
  }
}

/// Only requests made by this Baboon installation are included.
/// This is NOT the Groq organization's total usage or its daily TPD balance.
class CloudDailyUsage {
  const CloudDailyUsage({
    required this.date,
    this.requests = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.lastRequest,
  });

  final String date;
  final int requests;
  final int promptTokens;
  final int completionTokens;
  final CloudTokenUsage? lastRequest;
  int get totalTokens => promptTokens + completionTokens;

  CloudDailyUsage adding(CloudTokenUsage usage) => CloudDailyUsage(
    date: date,
    requests: requests + 1,
    promptTokens: promptTokens + usage.promptTokens,
    completionTokens: completionTokens + usage.completionTokens,
    lastRequest: usage,
  );

  Map<String, Object?> toJson() => {
    'date': date,
    'requests': requests,
    'prompt': promptTokens,
    'completion': completionTokens,
    if (lastRequest != null) 'lastRequest': lastRequest!.toJson(),
  };

  static CloudDailyUsage? fromJson(Object? value) {
    if (value is! Map) return null;
    final date = value['date'];
    if (date is! String) return null;
    return CloudDailyUsage(
      date: date,
      requests: (value['requests'] as num?)?.toInt() ?? 0,
      promptTokens: (value['prompt'] as num?)?.toInt() ?? 0,
      completionTokens: (value['completion'] as num?)?.toInt() ?? 0,
      lastRequest: CloudTokenUsage.fromJson(value['lastRequest']),
    );
  }
}

String cloudLocalDay([DateTime? date]) {
  final d = (date ?? DateTime.now()).toLocal();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Quota data sent by Groq, NOT estimated from locally counted tokens.
/// Per API docs requests are per day; tokens are per minute.
class GroqQuota {
  const GroqQuota({
    required this.model,
    required this.receivedAt,
    this.requestLimit,
    this.requestsRemaining,
    this.minuteTokenLimit,
    this.minuteTokensRemaining,
    this.requestsReset,
    this.tokensReset,
  });

  final String model;
  final DateTime receivedAt;
  final int? requestLimit;
  final int? requestsRemaining;
  final int? minuteTokenLimit;
  final int? minuteTokensRemaining;
  final String? requestsReset;
  final String? tokensReset;

  static GroqQuota fromHeaders(
      String model, Map<String, String?> headers, DateTime now) {
    int? number(String key) => int.tryParse(headers[key] ?? '');
    return GroqQuota(
      model: model,
      receivedAt: now,
      requestLimit: number('x-ratelimit-limit-requests'),
      requestsRemaining: number('x-ratelimit-remaining-requests'),
      minuteTokenLimit: number('x-ratelimit-limit-tokens'),
      minuteTokensRemaining: number('x-ratelimit-remaining-tokens'),
      requestsReset: headers['x-ratelimit-reset-requests'],
      tokensReset: headers['x-ratelimit-reset-tokens'],
    );
  }
}

/// Pure request builder: always uses fixed HTTPS endpoints (never user URLs).
/// Groq reasoning is hidden so it does not leak into displayed answer text.
Map<String, Object> buildCloudRequest(
    CloudProvider provider, String model, List<AiMessage> conversation) {
  final body = <String, Object>{
    'model': model,
    'messages': [
      for (final message in conversation)
        {'role': message.role, 'content': message.text},
    ],
    'stream': true,
    'max_tokens': 1024,
  };
  if (provider == CloudProvider.groq) {
    body['stream_options'] = {'include_usage': true};
    if (model.startsWith('openai/gpt-oss-')) {
      body['include_reasoning'] = false;
      body['reasoning_effort'] = model == 'openai/gpt-oss-20b' ? 'low' : 'medium';
    } else if (model.startsWith('qwen/')) {
      body['reasoning_format'] = 'hidden';
      body['reasoning_effort'] = 'none';
    }
  }
  return body;
}

/// Reads OpenAI-compatible SSE events. Supports multi-line events and [DONE].
Stream<String> cloudTextChunks(
  Stream<String> lines, {
  void Function(CloudTokenUsage usage)? onUsage,
}) async* {
  final dataLines = <String>[];
  String? parseData() {
    if (dataLines.isEmpty) return null;
    final result = dataLines.join('\n');
    dataLines.clear();
    return result;
  }

  String? parseContent(String? data) {
    if (data == null || data == '[DONE]') return null;
    final decoded = jsonDecode(data);
    if (decoded is! Map) return null;
    final usage = CloudTokenUsage.fromChunk(decoded);
    if (usage != null) onUsage?.call(usage);
    final error = decoded['error'];
    if (error != null) {
      final reason = error is Map ? error['message'] : error;
      throw StateError('Ошибка облачного API: ${reason ?? 'Неизвестная ошибка'}');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return null;
    final delta = (choices.first as Map)['delta'];
    if (delta is! Map) return null;
    final content = delta['content'];
    return content is String && content.isNotEmpty ? content : null;
  }

  await for (final line in lines) {
    if (line.isNotEmpty) {
      if (line.startsWith('data:')) dataLines.add(line.substring(5).trimLeft());
      continue;
    }
    final text = parseContent(parseData());
    if (text != null) yield text;
  }
  // Some HTTP streams end directly after their last data line.
  final last = parseContent(parseData());
  if (last != null) yield last;
}

class CloudAiEngine extends ChangeNotifier implements AiEngine {
  CloudAiEngine._();
  static final CloudAiEngine instance = CloudAiEngine._();

  final credentials = CloudCredentials.instance;
  HttpClient? _client;
  bool _stopped = false;
  // Keep the old getters for compatibility with existing settings code.
  int? get remainingRequests => groqQuota?.requestsRemaining;
  int? get remainingTokens => groqQuota?.minuteTokensRemaining;
  GroqQuota? groqQuota;

  final Map<CloudProvider, CloudDailyUsage> _daily = {};
  Future<void>? _usageLoading;
  CloudDailyUsage dailyUsageFor(CloudProvider provider) {
    final current = _daily[provider];
    final day = cloudLocalDay();
    return current?.date == day ? current! : CloudDailyUsage(date: day);
  }

  Future<void> ensureUsageLoaded() => _usageLoading ??= _loadUsage();

  Future<void> _loadUsage() async {
    try {
      for (final provider in CloudProvider.values) {
        final raw = await CloudCredentials.storage.read(
          key: 'baboon_usage_${provider.name}_v1',
        );
        if (raw != null) {
          final decoded = CloudDailyUsage.fromJson(jsonDecode(raw));
          if (decoded != null) _daily[provider] = decoded;
        }
      }
      notifyListeners();
    } catch (_) {
      // Tracking must never block inference when secure storage is unavailable.
      // Retain any counters already loaded, and allow a future retry.
      _usageLoading = null;
    }
  }

  Future<void> _recordUsage(CloudProvider provider, CloudTokenUsage usage) async {
    final updated = dailyUsageFor(provider).adding(usage);
    _daily[provider] = updated;
    notifyListeners();
    try {
      await CloudCredentials.storage.write(
        key: 'baboon_usage_${provider.name}_v1',
        value: jsonEncode(updated.toJson()),
      );
    } catch (_) {
      // The answer remains valid even if local stats cannot be persisted.
    }
  }

  @override
  Future<void> loadModel(String modelPath) => credentials.saveModel(credentials.provider, modelPath);

  @override
  Future<void> unloadModel() => stop();

  Future<void> stop() async {
    _stopped = true;
    _client?.close(force: true);
    _client = null;
  }

  void _readQuota(HttpHeaders headers, String model) {
    const names = <String>[
      'x-ratelimit-limit-requests',
      'x-ratelimit-remaining-requests',
      'x-ratelimit-limit-tokens',
      'x-ratelimit-remaining-tokens',
      'x-ratelimit-reset-requests',
      'x-ratelimit-reset-tokens',
    ];
    final values = <String, String?>{
      for (final name in names) name: headers.value(name),
    };
    groqQuota = GroqQuota.fromHeaders(model, values, DateTime.now());
    notifyListeners();
  }

  @override
  Stream<String> streamReply(List<AiMessage> conversation) async* {
    await credentials.load();
    await ensureUsageLoaded();
    final provider = credentials.provider;
    final key = await credentials.readKey(provider);
    if (key == null || key.trim().isEmpty) {
      throw StateError('Нет ключа ${provider.title}. Открой Настройки → Облачный ИИ.');
    }
    _stopped = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 60);
    _client = client;
    var received = false;
    CloudTokenUsage? requestUsage;
    try {
      final request = await client.postUrl(provider.endpoint);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.followRedirects = false;
      if (provider == CloudProvider.openrouter) {
        request.headers.set('HTTP-Referer', 'https://github.com/arladiy96-commits/Intellect-');
        request.headers.set('X-Title', 'Baboon AI');
      }
      request.add(utf8.encode(jsonEncode(buildCloudRequest(
          provider, credentials.model, conversation))));
      final response = await request.close();
      if (provider == CloudProvider.groq) {
        _readQuota(response.headers, credentials.model);
      }
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        var detail = 'HTTP ${response.statusCode}';
        try {
          final error = jsonDecode(body);
          if (error is Map) {
            final value = error['error'];
            if (value is Map) detail = value['message']?.toString() ?? detail;
            if (value is String) detail = value;
          }
        } on FormatException {
          // Do not show raw body or internal HTTP details.
        }
        if (response.statusCode == HttpStatus.tooManyRequests) {
          final retry = response.headers.value('retry-after');
          detail = 'Лимит запросов исчерпан${retry == null ? '' : '. Повтори через $retry с'}. $detail';
        } else if (response.statusCode == HttpStatus.unauthorized) {
          detail = 'Неверный API-ключ. Проверь ключ ${provider.title}.';
        }
        throw StateError('${provider.title}: $detail');
      }
      final lines = utf8.decoder.bind(response)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 60));
      await for (final piece in cloudTextChunks(
          lines, onUsage: (usage) => requestUsage = usage)) {
        if (_stopped) break;
        received = true;
        yield piece;
      }
      if (!_stopped && requestUsage != null) {
        await _recordUsage(provider, requestUsage!);
      }
      if (!received && !_stopped) {
        throw StateError('${provider.title} не вернул текст. Попробуй другую модель.');
      }
    } on SocketException catch (error) {
      if (!_stopped) throw StateError('Ошибка сети: ${error.message}');
    } on TimeoutException {
      if (!_stopped) throw StateError('Ответ облачной модели слишком долго не поступает');
    } on HttpException catch (error) {
      if (!_stopped) throw StateError('Ошибка соединения: ${error.message}');
    } catch (_) {
      if (!_stopped) rethrow;
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
Stream<String> cloudTextChunks(Stream<String> lines) async* {
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

class CloudAiEngine implements AiEngine {
  CloudAiEngine._();
  static final CloudAiEngine instance = CloudAiEngine._();

  final credentials = CloudCredentials.instance;
  HttpClient? _client;
  bool _stopped = false;
  int? remainingRequests;
  int? remainingTokens;

  @override
  Future<void> loadModel(String modelPath) => credentials.saveModel(credentials.provider, modelPath);

  @override
  Future<void> unloadModel() => stop();

  Future<void> stop() async {
    _stopped = true;
    _client?.close(force: true);
    _client = null;
  }

  void _readQuota(HttpHeaders headers) {
    remainingRequests = int.tryParse(headers.value('x-ratelimit-remaining-requests') ?? '');
    remainingTokens = int.tryParse(headers.value('x-ratelimit-remaining-tokens') ?? '');
  }

  @override
  Stream<String> streamReply(List<AiMessage> conversation) async* {
    await credentials.load();
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
      _readQuota(response.headers);
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
      await for (final piece in cloudTextChunks(lines)) {
        if (_stopped) break;
        received = true;
        yield piece;
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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/ai/ai_engine.dart';
import 'package:moy_ai/src/core/ai/cloud_ai_engine.dart';

void main() {
  test('Groq and OpenRouter API endpoints differ', () {
    expect(CloudProvider.groq.endpoint.host, 'api.groq.com');
    expect(CloudProvider.openrouter.endpoint.host, 'openrouter.ai');
  });

  test('Groq request hides chain of thought', () {
    final body = buildCloudRequest(CloudProvider.groq,
        'openai/gpt-oss-120b', [const AiMessage(role: 'user', text: 'Привет')]);
    expect(body['model'], 'openai/gpt-oss-120b');
    expect(body['include_reasoning'], false);
    expect(body['reasoning_effort'], 'medium');
    expect(body['stream'], true);
  });

  test('OpenRouter request does not include Groq-only fields', () {
    final body = buildCloudRequest(CloudProvider.openrouter,
        'openrouter/free', [const AiMessage(role: 'user', text: 'Тест')]);
    expect(body.containsKey('include_reasoning'), false);
    expect(body.containsKey('reasoning_format'), false);
  });

  test('SSE parser joins event chunks and respects done', () async {
    final stream = Stream<String>.fromIterable([
      'data: {"choices":[{"delta":{"content":"При"}}]}',
      '',
      ': keepalive',
      '',
      'data: {"choices":[{"delta":{"content":"вет"}}]}',
      '',
      'data: [DONE]',
      '',
    ]);
    expect(await cloudTextChunks(stream).toList(), ['При', 'вет']);
  });

  test('SSE parser accepts last event without final blank line', () async {
    expect(await cloudTextChunks(Stream<String>.fromIterable([
      'data: {"choices":[{"delta":{"content":"Конец"}}]}',
    ])).toList(), ['Конец']);
  });

  test('SSE inline error becomes an exception', () async {
    expect(
      cloudTextChunks(Stream<String>.fromIterable([
        'data: {"error":{"message":"quota"}}',
        '',
      ])).toList(),
      throwsA(isA<StateError>()),
    );
  });
}

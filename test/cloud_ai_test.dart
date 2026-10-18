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
    expect((body['stream_options'] as Map)['include_usage'], true);
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
  test('SSE usage event is counted even when choices is empty', () async {
    final updates = <CloudTokenUsage>[];
    final chunks = await cloudTextChunks(Stream<String>.fromIterable([
      'data: {"choices":[{"delta":{"content":"Привет"}}]}',
      '',
      'data: {"model":"openai/gpt-oss-120b","choices":[],"usage":{"prompt_tokens":120,"completion_tokens":42,"total_tokens":162}}',
      '',
      'data: [DONE]',
      '',
    ]), onUsage: updates.add).toList();
    expect(chunks, ['Привет']);
    expect(updates.length, 1);
    expect(updates.first.promptTokens, 120);
    expect(updates.first.completionTokens, 42);
    expect(updates.first.totalTokens, 162);
  });

  test('Groq quota identifies RPD separately from TPM', () {
    final quota = GroqQuota.fromHeaders('openai/gpt-oss-120b', {
      'x-ratelimit-limit-requests': '1000',
      'x-ratelimit-remaining-requests': '999',
      'x-ratelimit-limit-tokens': '8000',
      'x-ratelimit-remaining-tokens': '7650',
    }, DateTime(2026, 10, 19));
    expect(quota.requestLimit, 1000);
    expect(quota.requestsRemaining, 999);
    expect(quota.minuteTokenLimit, 8000);
    expect(quota.minuteTokensRemaining, 7650);
  });

  test('Device daily usage survives JSON and separates different days', () {
    final today = CloudDailyUsage(date: '2026-10-19').adding(
      const CloudTokenUsage(promptTokens: 100, completionTokens: 50,
          totalTokens: 150, model: 'openai/gpt-oss-120b'));
    final restored = CloudDailyUsage.fromJson(today.toJson())!;
    expect(restored.requests, 1);
    expect(restored.totalTokens, 150);
    expect(restored.lastRequest?.completionTokens, 50);
  });

}

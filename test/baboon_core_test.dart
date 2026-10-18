import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/core/baboon/baboon_core.dart';
import 'package:moy_ai/src/core/ai/ai_engine.dart';
import 'package:moy_ai/src/core/baboon/math_tool.dart';
import 'package:moy_ai/src/core/baboon/model_registry.dart';
import 'package:moy_ai/src/core/baboon/tool_registry.dart';
import 'package:moy_ai/src/core/knowledge/knowledge_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MathTool computes equations without an AI model', () async {
    final tool = MathTool();
    expect(MathTool.canSolve('Реши уравнение: x + 35 = 82'), isTrue);
    final result = await tool.execute({'expression': 'Реши уравнение: x + 35 = 82'});
    expect(result.success, isTrue);
    expect(result.message, contains('x = 47'));
    expect(result.message, contains('47 + 35 = 82'));
  });

  test('MathTool handles reversed unknown and refuses division by zero', () async {
    final tool = MathTool();
    final result = await tool.execute({'expression': '80 - x = 25'});
    expect(result.success, isTrue);
    expect(result.message, contains('x = 55'));
    final broken = await tool.execute({'expression': '5 / 0'});
    expect(broken.success, isFalse);
    expect(MathTool.canSolve('Что такое GPT-OSS 120B?'), isFalse);
  });

  test('Registry enforces allowlisted tools', () async {
    final registry = ToolRegistry()..register(MathTool());
    final denied = await registry.execute('math.basic', {'expression': '2+2'},
        allowedTools: {'other'});
    expect(denied.success, isFalse);
    final allowed = await registry.execute('math.basic', {'expression': '2+2'},
        allowedTools: {'math.basic'});
    expect(allowed.message, contains('= 4'));
  });

  test('Model catalog filters by offline/network permissions', () {
    final models = BaboonModelRegistry();
    models.register(const BaboonModelInfo(id: 'cloud', title: 'Cloud',
        skills: {BaboonModelSkill.chat}, requiresNetwork: true));
    models.register(const BaboonModelInfo(id: 'offline', title: 'Offline',
        skills: {BaboonModelSkill.chat}, requiresNetwork: false));
    final candidates = models.candidates(BaboonModelSkill.chat,
        availableIds: {'cloud', 'offline'}, allowNetwork: false);
    expect(candidates.map((e) => e.id).toList(), ['offline']);
  });

  test('Core routes explicit knowledge queries without guessing', () async {
    final folder = await Directory.systemTemp.createTemp('baboon-test-');
    try {
      final knowledge = KnowledgeRepository(directoryProvider: () async => folder);
      await knowledge.addDocument(collectionId: KnowledgeRepository.generalId,
          title: 'Учебник математики', content: 'Уравнение — равенство с неизвестным.');
      final core = BaboonCore(knowledge: knowledge);
      expect(core.selectTool('x + 35 = 82'), 'math.basic');
      expect(core.selectTool('найди в базе уравнение'), 'knowledge.search');
      expect(core.selectTool('Привет, как дела?'), isNull);
      final safe = core.cloudSafeHistory([
        const AiMessage(role: 'user', text: 'найди в базе уравнение'),
        const AiMessage(role: 'assistant', text: 'Личный документ из базы'),
        const AiMessage(role: 'user', text: 'Привет'),
      ]);
      expect(safe.length, 1);
      expect(safe.single.text, 'Привет');
      final answer = await core.tryTool('найди в базе уравнение');
      expect(answer!.message, contains('Учебник математики'));
      final unknown = await core.tryTool('найди в базе динозавробиология');
      expect(unknown!.message, contains('ничего подходящего не найдено'));
    } finally {
      await folder.delete(recursive: true);
    }
  });
}

import '../agents/agent_tool.dart';
import '../ai/ai_engine.dart';
import '../knowledge/knowledge_repository.dart';
import 'knowledge_search_tool.dart';
import 'math_tool.dart';
import 'model_registry.dart';
import 'tool_registry.dart';

class BaboonCore {
  BaboonCore({required KnowledgeRepository knowledge}) {
    tools.register(MathTool());
    tools.register(KnowledgeSearchTool(knowledge));
    models.register(const BaboonModelInfo(
      id: 'groq/openai/gpt-oss-120b', title: 'Groq · GPT-OSS 120B',
      skills: {BaboonModelSkill.chat, BaboonModelSkill.reasoning, BaboonModelSkill.coding},
      requiresNetwork: true));
    models.register(const BaboonModelInfo(
      id: 'groq/openai/gpt-oss-20b', title: 'Groq · GPT-OSS 20B',
      skills: {BaboonModelSkill.chat, BaboonModelSkill.reasoning},
      requiresNetwork: true));
    models.register(const BaboonModelInfo(
      id: 'openrouter', title: 'OpenRouter',
      skills: {BaboonModelSkill.chat}, requiresNetwork: true));
    models.register(const BaboonModelInfo(
      id: 'local/qwen', title: 'Локальная Qwen',
      skills: {BaboonModelSkill.chat, BaboonModelSkill.offline},
      requiresNetwork: false));
  }

  static final BaboonCore instance = BaboonCore(knowledge: KnowledgeRepository.instance);
  final ToolRegistry tools = ToolRegistry();
  final BaboonModelRegistry models = BaboonModelRegistry();

  String? selectTool(String question) {
    if (MathTool.canSolve(question)) return 'math.basic';
    final normalized = question.trim().toLowerCase();
    if (normalized.startsWith('найди в базе ') ||
        normalized.startsWith('поиск в знаниях:') ||
        normalized.startsWith('найди в знаниях ')) return 'knowledge.search';
    return null;
  }

  bool canHandle(String question) => selectTool(question) != null;

  /// Keep local knowledge-search turns out of later cloud context. A user can
  /// still deliberately paste text into a new cloud message, but previously
  /// retrieved document excerpts are not uploaded as conversation history.
  List<AiMessage> cloudSafeHistory(List<AiMessage> history) {
    final result = <AiMessage>[];
    for (var i = 0; i < history.length; i++) {
      final item = history[i];
      if (item.role == 'user' && selectTool(item.text) == 'knowledge.search') {
        if (i + 1 < history.length && history[i + 1].role == 'assistant') i++;
        continue;
      }
      result.add(item);
    }
    return result;
  }

  Future<ToolResult?> tryTool(String question) async {
    final id = selectTool(question);
    if (id == null) return null;
    if (id == 'math.basic') {
      return tools.execute(id, {'expression': question}, allowedTools: {id});
    }
    return tools.execute(id, {'query': question}, allowedTools: {id});
  }
}

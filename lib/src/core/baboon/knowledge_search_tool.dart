import '../agents/agent_tool.dart';
import '../knowledge/knowledge_repository.dart';

/// Strict citation-based search. No LLM guesses when documents are missing.
class KnowledgeSearchTool implements AgentTool {
  KnowledgeSearchTool(this.repository);
  final KnowledgeRepository repository;

  @override
  String get id => 'knowledge.search';

  @override
  Future<ToolResult> execute(Map<String, Object?> arguments) async {
    final input = arguments['query'];
    if (input is! String || input.trim().isEmpty) {
      return const ToolResult(success: false, message: 'Введи текст для поиска.');
    }
    final hits = await repository.search(input, limit: 5);
    if (hits.isEmpty) {
      return const ToolResult(success: true,
        message: 'В моей базе знаний ничего подходящего не найдено. Я не буду придумывать источник.');
    }
    final output = StringBuffer('Найдено в базе знаний:\n\n');
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      output.writeln('${i + 1}. ${hit.document.title}');
      output.writeln('Источник: ${hit.document.sourceName}');
      output.writeln(hit.excerpt);
      if (i != hits.length - 1) output.writeln();
    }
    return ToolResult(success: true, message: output.toString().trim());
  }
}

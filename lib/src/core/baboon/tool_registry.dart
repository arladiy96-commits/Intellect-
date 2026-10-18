import '../agents/agent_tool.dart';

/// Small permission-friendly registry. Tools never run because a model wrote
/// arbitrary Dart code: they must be installed and called by their exact ID.
class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  Iterable<String> get ids => _tools.keys;
  bool contains(String id) => _tools.containsKey(id);

  void register(AgentTool tool) {
    if (tool.id.trim().isEmpty || _tools.containsKey(tool.id)) {
      throw StateError('Инструмент с таким ID уже зарегистрирован: ${tool.id}');
    }
    _tools[tool.id] = tool;
  }

  Future<ToolResult> execute(String id, Map<String, Object?> arguments,
      {Set<String>? allowedTools}) async {
    if (allowedTools != null && !allowedTools.contains(id)) {
      return const ToolResult(success: false, message: 'Нет разрешения на этот инструмент.');
    }
    final tool = _tools[id];
    if (tool == null) {
      return ToolResult(success: false, message: 'Инструмент «$id» не установлен.');
    }
    try {
      return await tool.execute(Map.unmodifiable(arguments));
    } on FormatException catch (error) {
      return ToolResult(success: false, message: 'Некорректный ввод: ${error.message}');
    }
  }
}

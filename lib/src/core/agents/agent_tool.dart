/// Tools need explicit permissions and a record of each action.
abstract interface class AgentTool {
  String get id;
  Future<ToolResult> execute(Map<String, Object?> arguments);
}

class ToolResult {
  final bool success;
  final String message;
  const ToolResult({required this.success, required this.message});
}

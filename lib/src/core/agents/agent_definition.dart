class AgentDefinition {
  final String id;
  final String title;
  final String instructions;
  final Set<String> allowedTools;

  const AgentDefinition({
    required this.id,
    required this.title,
    required this.instructions,
    this.allowedTools = const {},
  });
}

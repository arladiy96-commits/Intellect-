/// Contract for both native llama.cpp and optional cloud providers.
abstract interface class AiEngine {
  Future<void> loadModel(String modelPath);
  Stream<String> streamReply(List<AiMessage> conversation);
  Future<void> unloadModel();
}

/// Immutable conversation record. Optional metadata keeps old call sites and
/// pre-SQLite JSON exports backwards compatible.
class AiMessage {
  const AiMessage({
    required this.role,
    required this.text,
    this.id,
    this.createdAt,
    this.status = 'completed',
    this.modelId,
    this.kind = 'text',
  });

  final String role;
  final String text;
  final String? id;
  final DateTime? createdAt;
  /// queued, generating, completed, interrupted, failed.
  final String status;
  final String? modelId;
  /// Reserved for text, attachment, tool_call and tool_result.
  final String kind;

  AiMessage copyWith({String? text, String? status, String? modelId}) =>
      AiMessage(
        role: role,
        text: text ?? this.text,
        id: id,
        createdAt: createdAt,
        status: status ?? this.status,
        modelId: modelId ?? this.modelId,
        kind: kind,
      );

  Map<String, dynamic> toJson() => {
    'role': role, 'text': text,
    if (id != null) 'id': id,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'status': status,
    if (modelId != null) 'modelId': modelId,
    'kind': kind,
  };

  factory AiMessage.fromJson(Map<String, dynamic> data,
      {required String fallbackId}) {
    final role = data['role'];
    if (!const {'user', 'assistant'}.contains(role)) {
      throw const FormatException('Неизвестная роль');
    }
    final status = data['status'];
    final kind = data['kind'];
    return AiMessage(
      id: data['id']?.toString() ?? fallbackId,
      role: role as String,
      text: data['text'] as String,
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      status: const {'queued', 'generating', 'completed', 'interrupted', 'failed'}
              .contains(status) ? status as String : 'completed',
      modelId: data['modelId']?.toString(),
      kind: const {'text', 'attachment', 'tool_call', 'tool_result'}
              .contains(kind) ? kind as String : 'text',
    );
  }
}

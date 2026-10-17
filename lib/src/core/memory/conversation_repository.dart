import '../ai/ai_engine.dart';

/// Future storage API. No conversation data is persisted in bootstrap.
abstract interface class ConversationRepository {
  Future<void> save(String conversationId, List<AiMessage> messages);
  Future<List<AiMessage>> load(String conversationId);
}

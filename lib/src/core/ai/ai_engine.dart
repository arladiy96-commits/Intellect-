/// Contract for both native llama.cpp and optional cloud providers.
abstract interface class AiEngine {
  Future<void> loadModel(String modelPath);
  Stream<String> streamReply(List<AiMessage> conversation);
  Future<void> unloadModel();
}

class AiMessage {
  final String role;
  final String text;
  const AiMessage({required this.role, required this.text});
}

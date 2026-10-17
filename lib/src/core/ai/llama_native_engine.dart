import 'ai_engine.dart';

/// Future JNI/FFI integration point. This bootstrap does NOT run GGUF models.
class LlamaNativeEngine implements AiEngine {
  @override
  Future<void> loadModel(String modelPath) =>
      Future.error(UnimplementedError('llama.cpp Android integration pending'));

  @override
  Stream<String> streamReply(List<AiMessage> conversation) =>
      Stream.error(UnimplementedError('llama.cpp Android integration pending'));

  @override
  Future<void> unloadModel() async {}
}

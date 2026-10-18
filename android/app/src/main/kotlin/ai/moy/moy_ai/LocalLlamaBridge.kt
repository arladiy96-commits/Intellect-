package ai.moy.moy_ai

/** JNI binding. Only called on the single inference executor, except nativeStop(). */
object LocalLlamaBridge {
    init { System.loadLibrary("moy_ai_native") }

    external fun nativeLoad(path: String, threads: Int): String?
    external fun nativeUnload()
    external fun nativeGenerate(roles: Array<String>, messages: Array<String>, maxTokens: Int): String?
    external fun nativeStop()

    // Registered from MainActivity; C++ calls this on its generation thread.
    @Volatile var onToken: ((String) -> Unit)? = null
    @Suppress("unused")
    fun emitToken(text: String) { onToken?.invoke(text) }

    @Volatile var onPerformance: ((Double, Double, Double, Int) -> Unit)? = null
    @Suppress("unused")
    fun emitPerformance(prefillMs: Double, tokensPerSecond: Double,
                        totalMs: Double, generatedTokens: Int) {
        onPerformance?.invoke(prefillMs, tokensPerSecond, totalMs, generatedTokens)
    }
}

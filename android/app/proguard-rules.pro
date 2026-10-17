# C++ llama_bridge.cpp obtains the Kotlin object with JNI and invokes
# LocalLlamaBridge.emitToken(String) via GetMethodID/CallVoidMethod.
# R8 only sees a reflective JNI call, so release shrinking can rename/remove it.
# Keep this class, its native declarations, and the exact callback name.
-keep class ai.moy.moy_ai.LocalLlamaBridge { *; }

#include <jni.h>
#include "llama.h"
#include "ggml-backend.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <exception>
#include <memory>
#include <string>
#include <vector>

namespace {
llama_model * g_model = nullptr;
llama_context * g_ctx = nullptr;
std::atomic<bool> g_stop{false};
bool g_backend_initialized = false;

// Do not call load/unload/generate concurrently: Kotlin runs them on one executor.
std::string as_string(JNIEnv * env, jstring s) {
    if (!s) return {};
    const char * utf = env->GetStringUTFChars(s, nullptr);
    if (!utf) return {};
    std::string value(utf);
    env->ReleaseStringUTFChars(s, utf);
    return value;
}

jstring fail(JNIEnv * env, const std::string & error) {
    return env->NewStringUTF(error.c_str());
}

void clear_model() {
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
}

// Token bytes can be split within a UTF-8 character. Emit only complete strings
// because JNI NewStringUTF cannot safely handle incomplete UTF-8 sequences.
size_t valid_prefix(const std::string & s) {
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t n = 1;
        if (c < 0x80) n = 1;
        else if ((c & 0xE0) == 0xC0) n = 2;
        else if ((c & 0xF0) == 0xE0) n = 3;
        else if ((c & 0xF8) == 0xF0) n = 4;
        else { ++i; continue; }
        if (i + n > s.size()) break;
        size_t j = 1;
        while (j < n && (static_cast<unsigned char>(s[i+j]) & 0xC0) == 0x80) ++j;
        if (j < n) { ++i; continue; }
        i += n;
    }
    return i;
}

void emit(JNIEnv * env, jobject receiver, jmethodID emit_method, std::string & pending) {
    size_t size = valid_prefix(pending);
    if (!size) return;
    std::string complete = pending.substr(0, size);
    pending.erase(0, size);
    jstring part = env->NewStringUTF(complete.c_str());
    if (!part) return;
    env->CallVoidMethod(receiver, emit_method, part);
    env->DeleteLocalRef(part);
}

void batch_set(llama_batch_ext * batch, const llama_token * tokens, int count, llama_pos first) {
    llama_batch_ext_clear(batch);
    for (int i = 0; i < count; ++i) {
        int index = llama_batch_ext_add_token(batch, 0, tokens[i]);
        const llama_pos pos = first + i;
        llama_batch_ext_set_pos(batch, index, &pos);
    }
    llama_batch_ext_set_output_logits(batch, count - 1, true);
}

// Mobile Vulkan adapters normally use host RAM and are registered as IGPU.
// A lookup for only GPU misses these devices even if Vulkan works correctly.
ggml_backend_dev_t find_gpu_device() {
    ggml_backend_dev_t device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
    if (!device) {
        device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);
    }
    return device;
}

// Returns the GPU name only after the user opts in to GPU mode. Avoids
// explicit GPU probing at regular app startup.
jstring native_gpu_description(JNIEnv * env, jobject) {
    ggml_backend_dev_t dev = find_gpu_device();
    if (!dev) return nullptr;
    const char * description = ggml_backend_dev_description(dev);
    return env->NewStringUTF(description ? description : "Vulkan GPU");
}

jstring native_load(JNIEnv * env, jobject, jstring jpath, jint requested_threads, jint requested_gpu_layers) {
    clear_model();
    const auto path = as_string(env, jpath);
    if (path.empty()) return fail(env, "Путь к GGUF пуст");
    if (!g_backend_initialized) {
        llama_backend_init();
        g_backend_initialized = true;
    }
    auto model_params = llama_model_default_params();
    const int gpu_layers = std::clamp<int>(requested_gpu_layers, 0, 99);
    if (gpu_layers > 0) {
        // Fail cleanly on unsupported Vulkan devices. Kotlin retries in CPU mode.
        if (!find_gpu_device()) {
            return fail(env, "Vulkan GPU недоступен в этой конфигурации устройства");
        }
    }
    model_params.n_gpu_layers = gpu_layers;
    g_model = llama_model_load_from_file(path.c_str(), model_params);
    if (!g_model) return fail(env, "llama.cpp не смог открыть GGUF");
    auto params = llama_context_default_params();
    params.n_ctx = 2048;
    params.n_batch = 512;
    params.n_ubatch = 512;
    const int threads = std::clamp<int>(requested_threads, 1, 8);
    params.n_threads = threads;
    params.n_threads_batch = threads;
    g_ctx = llama_init_from_model(g_model, params);
    if (!g_ctx) {
        clear_model();
        return fail(env, "Недостаточно памяти для контекста модели");
    }
    return nullptr;
}

void native_unload(JNIEnv *, jobject) { clear_model(); }
void native_stop(JNIEnv *, jobject) { g_stop.store(true); }

jstring native_generate(JNIEnv * env, jobject receiver, jobjectArray roles, jobjectArray texts, jint max_tokens) {
    if (!g_model || !g_ctx) return fail(env, "Модель не загружена");
    const int n = env->GetArrayLength(roles);
    if (!n || n != env->GetArrayLength(texts)) return fail(env, "Некорректная история сообщений");
    g_stop.store(false);
    using clock = std::chrono::steady_clock;
    const auto begun = clock::now();
    const auto elapsed_ms = [](clock::time_point a, clock::time_point b) {
        return std::chrono::duration<double, std::milli>(b - a).count();
    };

    std::vector<std::string> r, t;
    r.reserve(n + 1); t.reserve(n + 1);
    r.emplace_back("system");
    t.emplace_back("Ты полезный ИИ-помощник. Отвечай на русском языке. Отвечай сразу по существу, без вывода скрытых рассуждений.");
    for (int i=0; i<n; ++i) {
        auto jr = static_cast<jstring>(env->GetObjectArrayElement(roles, i));
        auto jt = static_cast<jstring>(env->GetObjectArrayElement(texts, i));
        std::string role = as_string(env, jr);
        if (role != "user" && role != "assistant" && role != "system") role = "user";
        r.emplace_back(role);
        t.emplace_back(as_string(env, jt));
        env->DeleteLocalRef(jr); env->DeleteLocalRef(jt);
    }
    const auto vocab = llama_model_get_vocab(g_model);
    const int32_t context_capacity = (int32_t)llama_n_ctx(g_ctx);
    // Keep space for the assistant answer and template overhead. Unlike a
    // character-count estimate, this checks the GGUF tokenizer exactly.
    const int reserved = std::min<int>(std::max<int>(max_tokens, 1), 512) + 32;
    const int prompt_budget = context_capacity - reserved;
    if (prompt_budget < 128) return fail(env, "Недостаточный размер контекста модели");

    std::vector<char> formatted;
    int size = 0;
    int length = 0;
    while (true) {
        std::vector<llama_chat_message> messages;
        messages.reserve(r.size());
        for (size_t i = 0; i < r.size(); ++i) messages.push_back({r[i].c_str(), t[i].c_str()});

        const char * tmpl = llama_model_chat_template(g_model, nullptr);
        if (!tmpl) tmpl = "chatml";
        size = llama_chat_apply_template(tmpl, messages.data(), (int)messages.size(), true, nullptr, 0);
        if (size <= 0) return fail(env, "Не удалось применить шаблон диалога модели");
        formatted.resize(size + 1);
        if (llama_chat_apply_template(tmpl, messages.data(), (int)messages.size(), true,
                                      formatted.data(), formatted.size()) < 0) {
            return fail(env, "Ошибка шаблона чата GGUF");
        }
        length = -llama_tokenize(vocab, formatted.data(), size, nullptr, 0, true, true);
        if (length <= 0) return fail(env, "Ошибка токенизации запроса");
        if (length <= prompt_budget) break;

        // Persisted messages stay intact; discard only old prompt turns.
        // Keep the built-in system prompt, and the newest user request.
        if (r.size() <= 2) {
            return fail(env, "Последний вопрос слишком длинный для контекста 2048. Сократи его.");
        }
        size_t oldest = 1;
        if (r[oldest] == "system" && r.size() > 3) oldest = 2;
        if (oldest >= r.size() - 1) oldest = 1; // discard optional memory first
        const bool is_user = r[oldest] == "user";
        r.erase(r.begin() + oldest);
        t.erase(t.begin() + oldest);
        if (is_user && oldest < r.size() - 1 && r[oldest] == "assistant") {
            r.erase(r.begin() + oldest);
            t.erase(t.begin() + oldest);
        }
    }
    std::vector<llama_token> prompt(length);
    if (llama_tokenize(vocab, formatted.data(), size, prompt.data(), prompt.size(), true, true) < 0) {
        return fail(env, "Ошибка токенизации диалога");
    }
    llama_memory_clear(llama_get_memory(g_ctx), true);
    llama_batch_ext * batch = llama_batch_ext_init(g_ctx);
    if (!batch) return fail(env, "Не удалось создать пакет токенов");
    llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!sampler) { llama_batch_ext_free(batch); return fail(env, "Не удалось создать sampler"); }
    llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05f, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.6f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    int generated_tokens = 0;
    clock::time_point first_sampled{};
    std::string error;
    auto emit_method = env->GetMethodID(env->GetObjectClass(receiver), "emitToken", "(Ljava/lang/String;)V");
    if (!emit_method) {
        env->ExceptionClear();
        error = "JNI emitToken не найден";
    } else {
        int position = 0;
        for (int start = 0; start < length && !g_stop.load(); start += 512) {
            int count = std::min(512, length - start);
            batch_set(batch, prompt.data() + start, count, position);
            if (llama_process(g_ctx, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
                error = "Ошибка обработки запроса llama.cpp";
                break;
            }
            position += count;
        }
        std::string pending;
        const int available = context_capacity - position;
        const int limit = std::min<int>(max_tokens, available);
        for (int i=0; i<limit && error.empty() && !g_stop.load(); ++i) {
            llama_token next = llama_sampler_sample(sampler, g_ctx, -1);
            if (llama_vocab_is_eog(vocab, next)) break;
            if (generated_tokens == 0) first_sampled = clock::now();
            ++generated_tokens;
            int nbytes = llama_token_to_piece(vocab, next, nullptr, 0, 0, true);
            if (nbytes >= 0) {
                std::string piece(nbytes, '\0');
                if (nbytes && llama_token_to_piece(vocab, next, piece.data(), piece.size(), 0, true) >= 0) {
                    pending += piece;
                    emit(env, receiver, emit_method, pending);
                }
            } else {
                std::string piece(-nbytes, '\0');
                if (llama_token_to_piece(vocab, next, piece.data(), piece.size(), 0, true) >= 0) {
                    pending += piece;
                    emit(env, receiver, emit_method, pending);
                }
            }
            if (env->ExceptionCheck()) { env->ExceptionClear(); error = "Ошибка передачи токена"; break; }
            if (i + 1 >= limit) break;
            batch_set(batch, &next, 1, position++);
            if (llama_process(g_ctx, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
                error = "Ошибка генерации llama.cpp";
                break;
            }
        }
        if (!pending.empty() && !env->ExceptionCheck()) {
            emit(env, receiver, emit_method, pending);
        }
    }
    const auto finished = clock::now();
    llama_sampler_free(sampler);
    llama_batch_ext_free(batch);
    if (!error.empty()) return fail(env, error);

    // Includes chat formatting, tokenization, prefill and sampling of the
    // first token. This is the actual delay before the first sampled token.
    // Decode tok/s excludes the first token, so it only measures generation.
    // If generation stopped before its first token, report elapsed time.
    const double prefill_ms = elapsed_ms(begun,
        generated_tokens > 0 ? first_sampled : finished);
    const double total_ms = elapsed_ms(begun, finished);
    const double decoding_ms = generated_tokens > 1
        ? elapsed_ms(first_sampled, finished) : 0.0;
    const double tokens_per_second = decoding_ms > 0
        ? (generated_tokens - 1) * 1000.0 / decoding_ms : 0.0;
    auto metrics_method = env->GetMethodID(env->GetObjectClass(receiver),
                                            "emitPerformance", "(DDDI)V");
    if (metrics_method) {
        env->CallVoidMethod(receiver, metrics_method, prefill_ms,
                            tokens_per_second, total_ms, generated_tokens);
        if (env->ExceptionCheck()) env->ExceptionClear();
    } else if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
    return nullptr;
}

JNINativeMethod methods[] = {
    {"nativeLoad", "(Ljava/lang/String;II)Ljava/lang/String;", reinterpret_cast<void *>(native_load)},
    {"nativeGpuDescription", "()Ljava/lang/String;", reinterpret_cast<void *>(native_gpu_description)},
    {"nativeUnload", "()V", reinterpret_cast<void *>(native_unload)},
    {"nativeGenerate", "([Ljava/lang/String;[Ljava/lang/String;I)Ljava/lang/String;", reinterpret_cast<void *>(native_generate)},
    {"nativeStop", "()V", reinterpret_cast<void *>(native_stop)},
};
} // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM * vm, void *) {
    JNIEnv * env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass klass = env->FindClass("ai/moy/moy_ai/LocalLlamaBridge");
    if (!klass) return JNI_ERR;
    if (env->RegisterNatives(klass, methods, sizeof(methods) / sizeof(methods[0])) != 0) return JNI_ERR;
    return JNI_VERSION_1_6;
}

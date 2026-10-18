package ai.moy.moy_ai

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "moy_ai/llama"
    private val eventsName = "moy_ai/llama_events"
    private val pickRequest = 7011
    private val worker = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPicker: MethodChannel.Result? = null
    @Volatile private var activeModelPath: String? = null
    private val prefs by lazy { getSharedPreferences("local_models_v1", MODE_PRIVATE) }

    // A GPU driver can kill the process without throwing a Kotlin exception.
    // On next launch reset to CPU, rather than crashing repeatedly at startup.
    private fun recoverInterruptedGpuLoad() {
        if (prefs.getBoolean("gpu_load_pending", false) ||
            prefs.getBoolean("gpu_run_pending", false)) {
            prefs.edit().putInt("gpu_layers", 0)
                .remove("gpu_load_pending").remove("gpu_run_pending")
                .putBoolean("gpu_recovered", true).commit()
        }
    }

    private fun emit(type: String, vararg values: Pair<String, Any?>) {
        val event = mutableMapOf<String, Any?>("type" to type)
        event.putAll(values)
        ui.post { eventSink?.success(event) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        recoverInterruptedGpuLoad()
        UpdateBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })
        LocalLlamaBridge.onToken = { token -> emit("token", "text" to token) }
        LocalLlamaBridge.onPerformance = { prefillMs, tps, totalMs, generatedTokens ->
            emit("performance", "prefillMs" to prefillMs,
                "tokensPerSecond" to tps, "totalMs" to totalMs,
                "generatedTokens" to generatedTokens)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getGpuLayers" -> result.success(prefs.getInt("gpu_layers", 0))
                    "getGpuRecovery" -> {
                        val recovered = prefs.getBoolean("gpu_recovered", false)
                        prefs.edit().remove("gpu_recovered").apply()
                        result.success(recovered)
                    }
                    "setGpuLayers" -> {
                        val layers = call.argument<Int>("layers") ?: 0
                        if (layers !in listOf(0, 8, 16, 32, 99)) {
                            result.error("INVALID_GPU", "Допустимы 0, 8, 16, 32 или 99 слоёв", null)
                        } else if (activeModelPath != null) {
                            result.error("MODEL_LOADED", "Сначала выгрузи модель", null)
                        } else {
                            prefs.edit().putInt("gpu_layers", layers).apply()
                            result.success(null)
                        }
                    }
                    "getCpuThreads" -> result.success(prefs.getInt("cpu_threads", 4))
                    "setCpuThreads" -> {
                        val threads = call.argument<Int>("threads") ?: 4
                        if (threads !in listOf(1, 2, 4, 6, 8)) {
                            result.error("INVALID_THREADS", "Допустимы 1, 2, 4, 6 или 8 потоков", null)
                        } else if (activeModelPath != null) {
                            result.error("MODEL_LOADED", "Сначала выгрузи модель", null)
                        } else {
                            prefs.edit().putInt("cpu_threads", threads).apply()
                            result.success(null)
                        }
                    }
                    "listModels" -> result.success(storedModels())
                    "importModel" -> {
                        if (pendingPicker != null) {
                            result.error("BUSY", "Уже открыт выбор файла", null)
                        } else {
                            pendingPicker = result
                            try {
                                val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "*/*"
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivityForResult(pick, pickRequest)
                            } catch (e: Exception) {
                                pendingPicker = null
                                result.error("PICKER", e.message, null)
                            }
                        }
                    }
                    "loadModel" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (storedModels().none { it["path"] == path }) {
                            result.error("NOT_FOUND", "Модель не найдена в каталоге приложения", null)
                        } else {
                            worker.execute {
                                try {
                                    LocalLlamaBridge.nativeUnload()
                                    activeModelPath = null
                                    val threads = prefs.getInt("cpu_threads", 4).coerceIn(1, 8)
                                    val requestedGpuLayers = prefs.getInt("gpu_layers", 0)
                                    var actualGpuLayers = requestedGpuLayers
                                    var fallbackReason: String? = null
                                    // Commit is deliberate: persists even after an abrupt native crash.
                                    if (requestedGpuLayers > 0) {
                                        prefs.edit().putBoolean("gpu_load_pending", true).commit()
                                    }
                                    var err = LocalLlamaBridge.nativeLoad(path, threads, requestedGpuLayers)
                                    if (err != null && requestedGpuLayers > 0) {
                                        fallbackReason = err
                                        // If GPU initialization fails, keep the model usable on CPU.
                                        actualGpuLayers = 0
                                        prefs.edit().putInt("gpu_layers", 0).commit()
                                        err = LocalLlamaBridge.nativeLoad(path, threads, 0)
                                    }
                                    val gpuName = if (err == null && actualGpuLayers > 0) {
                                        try { LocalLlamaBridge.nativeGpuDescription() } catch (_: Throwable) { null }
                                    } else null
                                    prefs.edit().remove("gpu_load_pending").commit()
                                    ui.post {
                                        if (err == null) {
                                            activeModelPath = path
                                            result.success(mapOf(
                                                "gpuLayers" to actualGpuLayers,
                                                "gpuName" to (gpuName ?: ""),
                                                "fallback" to (fallbackReason ?: "")
                                            ))
                                        } else result.error("LOAD_FAILED", err, null)
                                    }
                                } catch (e: Throwable) {
                                    ui.post { result.error("LOAD_FAILED", e.message, null) }
                                }
                            }
                        }
                    }
                    "unloadModel" -> worker.execute {
                        try {
                            LocalLlamaBridge.nativeUnload()
                            activeModelPath = null
                            ui.post { result.success(null) }
                        } catch (e: Throwable) {
                            ui.post { result.error("UNLOAD", e.message, null) }
                        }
                    }
                    "generate" -> {
                        val items = call.argument<List<Map<String, String>>>("messages") ?: emptyList()
                        val maxTokens = (call.argument<Int>("maxTokens") ?: 512).coerceIn(1, 1024)
                        if (activeModelPath == null) {
                            result.error("NOT_LOADED", "Модель не запущена", null)
                        } else {
                            // Respond immediately; tokens and completion arrive over EventChannel.
                            worker.execute {
                                try {
                                    val roles = items.map { it["role"] ?: "user" }.toTypedArray()
                                    val texts = items.map { it["text"] ?: "" }.toTypedArray()
                                    if (prefs.getInt("gpu_layers", 0) > 0) {
                                        prefs.edit().putBoolean("gpu_run_pending", true).commit()
                                    }
                                    val error = LocalLlamaBridge.nativeGenerate(roles, texts, maxTokens)
                                    if (error == null) emit("done")
                                    else emit("error", "message" to error)
                                } catch (e: Throwable) {
                                    emit("error", "message" to (e.message ?: "Ошибка nativeGenerate"))
                                } finally {
                                    prefs.edit().remove("gpu_run_pending").commit()
                                }
                            }
                            result.success(null)
                        }
                    }
                    "stop" -> {
                        LocalLlamaBridge.nativeStop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun storedModels(): List<Map<String, Any>> {
        val arr = JSONArray(prefs.getString("models", "[]"))
        val models = mutableListOf<Map<String, Any>>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val file = File(obj.optString("path"))
            if (file.isFile) models.add(mapOf(
                "name" to obj.optString("name", file.name),
                "path" to file.absolutePath,
                "bytes" to file.length()
            ))
        }
        return models
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val reply = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(null)
            return
        }
        worker.execute {
            var dest: File? = null
            try {
                val resolver = contentResolver
                var rawName = "model.gguf"
                var size = -1L
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        rawName = cursor.getString(0) ?: rawName
                        if (!cursor.isNull(1)) size = cursor.getLong(1)
                    }
                }
                if (!rawName.lowercase().endsWith(".gguf")) throw IllegalArgumentException("Выбери файл .gguf")
                val directory = File(filesDir, "gguf").apply { mkdirs() }
                if (size > directory.usableSpace) throw IllegalStateException("Недостаточно свободного места для копирования")
                val name = rawName.replace(Regex("[^a-zA-Z0-9._-]"), "_").take(100)
                var uniqueName = name
                var index = 1
                while (File(directory, uniqueName).exists()) {
                    uniqueName = "${index++}_$name"
                }
                val target = File(directory, uniqueName)
                dest = target
                resolver.openInputStream(uri).use { input ->
                    if (input == null) throw IllegalStateException("Не удалось открыть GGUF")
                    FileOutputStream(target).use { out ->
                        val buf = ByteArray(1024 * 1024)
                        var read: Int
                        var copied = 0L
                        var lastNotified = 0L
                        while (input.read(buf).also { read = it } >= 0) {
                            if (read == 0) continue
                            out.write(buf, 0, read)
                            copied += read
                            if (copied - lastNotified >= 16L * 1024 * 1024) {
                                lastNotified = copied
                                if (size > 0) emit("importProgress", "progress" to (copied.toDouble() / size).coerceIn(0.0, 1.0))
                            }
                        }
                    }
                }
                if (target.length() < 1024L * 1024) throw IllegalArgumentException("Файл слишком маленький для GGUF")
                val arr = JSONArray(prefs.getString("models", "[]"))
                arr.put(JSONObject().put("name", rawName).put("path", target.absolutePath))
                prefs.edit().putString("models", arr.toString()).apply()
                emit("importProgress", "progress" to 1.0)
                ui.post { reply.success(target.absolutePath) }
            } catch (e: Exception) {
                dest?.delete()
                ui.post { reply.error("IMPORT_FAILED", e.message, null) }
            }
        }
    }

    override fun onDestroy() {
        LocalLlamaBridge.onToken = null
        LocalLlamaBridge.onPerformance = null
        worker.execute { try { LocalLlamaBridge.nativeUnload() } catch (_: Throwable) { } }
        worker.shutdown()
        super.onDestroy()
    }
}

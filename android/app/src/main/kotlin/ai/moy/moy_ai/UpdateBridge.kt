package ai.moy.moy_ai

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/** Isolated native update bridge; never touches llama.cpp or model storage. */
object UpdateBridge {
    private const val CHANNEL = "baboon/update"

    fun register(activity: FlutterActivity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "buildNumber" -> {
                    val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                    result.success(info.longVersionCode)
                }
                "cachePath" -> {
                    val directory = File(activity.cacheDir, "updates").apply { mkdirs() }
                    result.success(directory.absolutePath)
                }
                "installVerified" -> {
                    val fileName = call.argument<String>("fileName") ?: ""
                    val sha = call.argument<String>("sha256") ?: ""
                    if (!Regex("^baboon-update-[0-9]+\\.apk$").matches(fileName) ||
                        !Regex("^[a-fA-F0-9]{64}$").matches(sha)) {
                        result.error("INVALID_ARGUMENT", "Неверное имя APK или SHA-256", null)
                    } else {
                        Thread {
                            try {
                                val root = File(activity.cacheDir, "updates").canonicalFile
                                val apk = File(root, fileName).canonicalFile
                                if (apk.parentFile != root || !apk.isFile || apk.length() < 1024L) {
                                    throw IllegalStateException("Файл обновления не найден")
                                }
                                val md = MessageDigest.getInstance("SHA-256")
                                apk.inputStream().buffered().use { input ->
                                    val buffer = ByteArray(1024 * 1024)
                                    while (true) {
                                        val len = input.read(buffer)
                                        if (len == -1) break
                                        md.update(buffer, 0, len)
                                    }
                                }
                                val actual = md.digest().joinToString("") { "%02x".format(it) }
                                if (!actual.equals(sha, ignoreCase = true)) {
                                    throw SecurityException("Контрольная сумма APK не совпадает")
                                }
                                activity.runOnUiThread {
                                    try {
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                            !activity.packageManager.canRequestPackageInstalls()) {
                                            val settingsIntent = Intent(
                                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                                Uri.parse("package:${activity.packageName}")
                                            )
                                            activity.startActivity(settingsIntent)
                                            result.success("permission_required")
                                            return@runOnUiThread
                                        }
                                        val uri = FileProvider.getUriForFile(
                                            activity,
                                            "${activity.packageName}.updateprovider",
                                            apk
                                        )
                                        val intent = Intent(Intent.ACTION_VIEW).apply {
                                            setDataAndType(uri, "application/vnd.android.package-archive")
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        activity.startActivity(intent)
                                        result.success("installer_opened")
                                    } catch (e: Exception) {
                                        result.error("INSTALL", e.message, null)
                                    }
                                }
                            } catch (e: Exception) {
                                activity.runOnUiThread { result.error("VERIFY", e.message, null) }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

package dev.amirzr.singbox.service

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.AtomicFile
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Только фиксированные служебные сообщения: конфигурации и тексты исключений сюда не передаются. */
object RuntimeDiagnostics {
    private val entries = mutableListOf<Map<String, Any>>()
    private var loaded = false
    private var exitsCollected = false
    private val lastCore = mutableMapOf<String, Long>()

    private fun file(context: Context) = AtomicFile(File(context.filesDir, "vpn-runtime-events.json"))

    @Synchronized
    private fun load(context: Context) {
        if (loaded) return
        loaded = true
        runCatching {
            val stored = file(context).openRead().bufferedReader().use { JSONArray(it.readText()) }
            for (i in 0 until stored.length()) {
                val e = stored.getJSONObject(i)
                entries.add(mapOf("id" to e.getString("id"), "time" to e.getLong("time"),
                    "level" to e.getString("level"), "message" to e.getString("message")))
            }
        }
    }

    @Synchronized
    fun record(context: Context, level: String, message: String,
               time: Long = System.currentTimeMillis(), id: String = "native_" + UUID.randomUUID()) {
        load(context)
        if (entries.any { it["id"] == id }) return
        entries.add(mapOf("id" to id, "time" to time, "level" to level, "message" to message))
        entries.sortBy { it["time"] as Long }
        var core = 0
        var lifecycle = 0
        val retained = entries.asReversed().filter {
            if ((it["id"] as String).startsWith("core_")) ++core <= 50 else ++lifecycle <= 150
        }.asReversed()
        entries.clear()
        entries.addAll(retained)
        val atomic = file(context)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomic.startWrite()
            val data = JSONArray()
            entries.forEach { data.put(JSONObject(it)) }
            stream.write(data.toString().toByteArray(Charsets.UTF_8))
            atomic.finishWrite(stream)
        } catch (_: Exception) {
            stream?.let { atomic.failWrite(it) }
            Log.w("RuntimeDiagnostics", "Не удалось сохранить служебный журнал")
        }
    }

    @Synchronized
    fun recordCore(context: Context, message: String) {
        val summary = CoreLogSummary.from(message) ?: return
        val key = summary.first + summary.second
        val now = android.os.SystemClock.elapsedRealtime()
        if (lastCore[key]?.let { now - it < 30_000L } == true) return
        lastCore[key] = now
        record(context, summary.first, summary.second, id = "core_" + UUID.randomUUID())
    }

    @Synchronized
    fun snapshot(context: Context): List<Map<String, Any>> {
        load(context)
        if (!exitsCollected && Build.VERSION.SDK_INT >= 30) {
            exitsCollected = true
            runCatching {
                val activity = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                activity.getHistoricalProcessExitReasons(context.packageName, 0, 10).forEach { exit ->
                    // Android-код сохраняется без description/tombstone, которые могут содержать секреты.
                    val reason = exitReason(exit.reason)
                    record(context, "warning", "Android: предыдущий процесс завершён ($reason; код ${exit.reason}, статус ${exit.status}). " +
                        "Запись относится к процессу приложения и сама по себе не доказывает сбой VPN.",
                        exit.timestamp, "exit_${exit.timestamp}_${exit.pid}_${exit.reason}")
                }
            }.onFailure {
                record(context, "warning", "Android не предоставил историю завершения процесса.")
            }
        }
        return entries.map { it.toMap() }
    }

    internal fun exitReason(code: Int): String = when (code) {
        1 -> "самостоятельный выход"
        2 -> "завершение сигналом"
        3 -> "нехватка памяти"
        4 -> "необработанное исключение"
        5 -> "сбой нативного кода"
        6 -> "приложение не отвечало (ANR)"
        7 -> "ошибка инициализации"
        8 -> "изменение разрешений"
        9 -> "избыточное потребление ресурсов"
        10 -> "запрос пользователя или системы управления приложениями"
        11 -> "остановка пользователем"
        12 -> "завершение зависимого процесса"
        14 -> "сбой заморозки процесса"
        15 -> "изменение состояния пакета"
        16 -> "обновление пакета"
        else -> "причина не уточнена системой"
    }

    fun watchPower(context: Context): () -> Unit {
        val app = context.applicationContext
        val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
        fun report() {
            record(app, "info", "Питание Android: экран=${power.isInteractive}, " +
                "Doze=${power.isDeviceIdleMode}, энергосбережение=${power.isPowerSaveMode}, " +
                "исключение оптимизации=${power.isIgnoringBatteryOptimizations(app.packageName)}.")
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { report() }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else app.registerReceiver(receiver, filter)
        report()
        return {
            try { app.unregisterReceiver(receiver) } catch (_: Exception) { /* Уже снят. */ }
        }
    }
}

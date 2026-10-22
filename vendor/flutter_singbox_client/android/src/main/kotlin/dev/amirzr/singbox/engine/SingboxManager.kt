package dev.amirzr.singbox.engine

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import dev.amirzr.singbox.SingboxConstants
import dev.amirzr.singbox.command.SingboxCommandClient
import dev.amirzr.singbox.service.SessionOptions
import dev.amirzr.singbox.service.SingboxProxyService
import dev.amirzr.singbox.service.SingboxVPNService
import dev.amirzr.singbox.service.RuntimeDiagnostics
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import org.json.JSONObject

/**
 * Stateless SDK orchestrator.
 *
 * Manages the service lifecycle and event dispatch only.
 * No profiles, settings, logs, or connections are stored here.
 * All configuration is passed at [connect] call time.
 */
class SingboxManager(private val context: Context) {

    companion object {
        private const val TAG = "SingboxManager"

        @Volatile
        private var _instance: SingboxManager? = null

        fun getInstance(context: Context): SingboxManager {
            return _instance ?: synchronized(this) {
                _instance ?: SingboxManager(context.applicationContext).also { _instance = it }
            }
        }

        internal fun resetForTest() {
            synchronized(this) { _instance = null }
        }
    }

    // ── Public streams ────────────────────────────────────────────────────────

    private val _serviceState = MutableStateFlow(SingboxConstants.STATE_STOPPED)
    val serviceState: StateFlow<Int> = _serviceState

    private val _trafficStats = MutableSharedFlow<Map<String, Any>>(replay = 1)
    val trafficStats: SharedFlow<Map<String, Any>> = _trafficStats

    private val _logs = MutableSharedFlow<List<Map<String, Any>>>(extraBufferCapacity = 128)
    val logs: SharedFlow<List<Map<String, Any>>> = _logs

    private val _connections = MutableSharedFlow<List<Map<String, Any>>>(replay = 1)
    val connections: SharedFlow<List<Map<String, Any>>> = _connections

    private val _groups = MutableSharedFlow<List<Map<String, Any>>>(replay = 1)
    val groups: SharedFlow<List<Map<String, Any>>> = _groups

    private val _clashMode = MutableSharedFlow<String>(replay = 1)
    val clashMode: SharedFlow<String> = _clashMode

    private val _clashModes = MutableSharedFlow<List<String>>(replay = 1)
    val clashModes: SharedFlow<List<String>> = _clashModes

    private val _alerts = MutableSharedFlow<String>(extraBufferCapacity = 32)
    val alerts: SharedFlow<String> = _alerts

    // ── Internals ─────────────────────────────────────────────────────────────

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var commandClient: SingboxCommandClient? = null
    private var clientGeneration = 0
    private var reconnectJob: Job? = null
    private var reconnectAttempts = 0
    @Volatile var stopRequested = false
        private set

    // ── Service lifecycle ─────────────────────────────────────────────────────

    fun connect(options: SessionOptions) {
        if (_serviceState.value != SingboxConstants.STATE_STOPPED) return
        stopRequested = false
        RuntimeDiagnostics.record(context, "info", "Запрошен запуск VPN-сервиса.")
        SingboxEngine.updateMemorySettings(
            enabled = options.memoryLimit.enabled,
            limitMb = options.memoryLimit.limitMb,
            killConnections = options.memoryLimit.killConnections,
        )
        val intent = buildServiceIntent(options.networkMode).apply {
            putExtra(SessionOptions.EXTRA_KEY, JSONObject(options.toMap()).toString())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        _serviceState.value = SingboxConstants.STATE_STARTING
    }

    suspend fun connectAwait(options: SessionOptions, timeoutMs: Long = 15_000L): Result<Unit> {
        connect(options)
        return try {
            withTimeout(timeoutMs) {
                serviceState
                    .filter { it == SingboxConstants.STATE_STARTED || it == SingboxConstants.STATE_STOPPED }
                    .first()
                    .let { state ->
                        if (state == SingboxConstants.STATE_STARTED) Result.success(Unit)
                        else Result.failure(RuntimeException("Service failed to start"))
                    }
            }
        } catch (e: TimeoutCancellationException) {
            Result.failure(RuntimeException("Service start timed out after ${timeoutMs}ms"))
        }
    }

    fun disconnect() {
        stopRequested = true
        RuntimeDiagnostics.record(context, "info", "Запрошено отключение пользователем или вызывающим приложением.")
        _serviceState.value = SingboxConstants.STATE_STOPPING
        reconnectJob?.cancel()
        disconnectCommandClient()
        val vpn = SingboxVPNService.instance
        val proxy = SingboxProxyService.instance
        when {
            vpn != null -> vpn.stopGracefully()
            proxy != null -> proxy.stopGracefully()
            else -> {
                context.stopService(Intent(context, SingboxVPNService::class.java))
                context.stopService(Intent(context, SingboxProxyService::class.java))
                notifyServiceState(SingboxConstants.STATE_STOPPED)
            }
        }
    }

    fun reloadConfig() {
        commandClient?.serviceReload()
    }

    fun dispose() {
        reconnectJob?.cancel()
        disconnectCommandClient()
        scope.cancel()
        synchronized(Companion) { _instance = null }
    }

    private fun buildServiceIntent(networkMode: String): Intent = when (networkMode) {
        SingboxConstants.MODE_PROXY -> Intent(context, SingboxProxyService::class.java)
        else -> Intent(context, SingboxVPNService::class.java)
    }

    // ── VPN permission ────────────────────────────────────────────────────────

    fun needsVPNPermission(): Intent? = VpnService.prepare(context)

    // ── CommandClient ─────────────────────────────────────────────────────────

    /** Attempt to connect to a service that may already be running (e.g. after a cold start). */
    fun tryConnectToRunningService() {
        // Повторная Activity использует уже подключённый менеджер сервиса.
        // Его переподключение создавало краткий STOPPED и гонку восстановления API.
        if (commandClient == null && _serviceState.value == SingboxConstants.STATE_STARTED) connectCommandClient()
    }

    private fun connectCommandClient() {
        disconnectCommandClient()
        val generation = clientGeneration
        // Поздний callback старого клиента не должен влиять на новый сеанс.
        val guarded = object : SingboxCommandClient.Handler by clientHandler {
            override fun onConnected() {
                scope.launch { if (generation == clientGeneration) clientHandler.onConnected() }
            }
            override fun onDisconnected(message: String) {
                scope.launch { if (generation == clientGeneration) clientHandler.onDisconnected(message) }
            }
        }
        commandClient = SingboxCommandClient(handler = guarded)
        commandClient?.connect()
    }

    private fun disconnectCommandClient() {
        clientGeneration++
        commandClient?.disconnect()
        commandClient = null
    }

    private val clientHandler = object : SingboxCommandClient.Handler {

        override fun onConnected() {
            if (_serviceState.value != SingboxConstants.STATE_STARTED) return
            if (reconnectAttempts > 0) RuntimeDiagnostics.record(context, "info", "Локальный канал управления восстановлен.")
            reconnectAttempts = 0
            Log.i(TAG, "CommandClient connected")
        }

        override fun onDisconnected(message: String) {
            // Состояние меняют только lifecycle сервиса и подтверждённый старт ядра.
            if (_serviceState.value != SingboxConstants.STATE_STARTED) return
            if (reconnectJob?.isActive == true) return
            RuntimeDiagnostics.record(context, "warning", "Потерян локальный канал управления. Остановка VPN-сервиса не подтверждена.")
            if (reconnectAttempts >= 3) {
                RuntimeDiagnostics.record(context, "warning", "Канал управления не восстановлен после трёх попыток. VPN-сервис не останавливался автоматически.")
                return
            }
            reconnectAttempts++
            reconnectJob = scope.launch {
                delay(1000L * reconnectAttempts)
                if (_serviceState.value == SingboxConstants.STATE_STARTED) connectCommandClient()
            }
        }

        override fun onStatus(stats: Map<String, Any>) {
            scope.launch { _trafficStats.emit(stats) }
        }

        override fun onLogs(entries: List<Map<String, Any>>) {
            entries.forEach { RuntimeDiagnostics.recordCore(context, it["message"] as? String ?: "") }
            scope.launch { _logs.emit(entries) }
        }

        override fun onGroups(groups: List<Map<String, Any>>) {
            scope.launch { _groups.emit(groups) }
        }

        override fun onConnections(conns: List<Map<String, Any>>) {
            scope.launch { _connections.emit(conns) }
        }

        override fun onClashModes(modes: List<String>, current: String) {
            scope.launch {
                _clashModes.emit(modes)
                _clashMode.emit(current)
            }
        }

        override fun onClashModeChanged(mode: String) {
            scope.launch { _clashMode.emit(mode) }
        }

        override fun onAlert(message: String) {
            scope.launch { _alerts.emit(message) }
        }
    }

    // ── Outbound / Clash / Connection actions ─────────────────────────────────

    fun selectOutbound(groupTag: String, outboundTag: String) {
        commandClient?.selectOutbound(groupTag, outboundTag)
    }

    fun urlTest(groupTag: String) {
        commandClient?.urlTest(groupTag)
    }

    fun setClashMode(mode: String) {
        commandClient?.setClashMode(mode)
    }

    fun closeConnection(id: String) {
        commandClient?.closeConnection(id)
    }

    fun closeAllConnections() {
        commandClient?.closeAllConnections()
    }

    // ── Point-in-time queries (delegate to CommandClient) ─────────────────────

    fun getTrafficSnapshot(): Map<String, Any> {
        return commandClient?.getLastStats() ?: mapOf(
            "uplinkBps" to 0, "downlinkBps" to 0,
            "uplinkTotalBytes" to 0, "downlinkTotalBytes" to 0,
            "memoryBytes" to 0, "goroutines" to 0,
            "connectionsIn" to 0, "connectionsOut" to 0,
        )
    }

    fun getSystemProxyStatus(): Map<String, Any> {
        return commandClient?.getSystemProxyStatus()
            ?: mapOf("available" to false, "enabled" to false)
    }

    fun setSystemProxyEnabled(enabled: Boolean) {
        commandClient?.setSystemProxyEnabled(enabled)
    }

    // ── Service state notifications (called by services) ──────────────────────

    fun notifyServiceStarted() {
        scope.launch {
        if (_serviceState.value != SingboxConstants.STATE_STARTING) return@launch
        reconnectAttempts = 0
        reconnectJob?.cancel()
        RuntimeDiagnostics.record(context, "info", "Ядро запущено; VPN-сервис работает. Доступность удалённого сервера проверяется отдельно.")
        _serviceState.value = SingboxConstants.STATE_STARTED
        connectCommandClient()
        }
    }

    fun notifyServiceState(state: Int) {
        _serviceState.value = state
        if (state == SingboxConstants.STATE_STOPPED) {
            reconnectJob?.cancel()
            reconnectAttempts = 0
            RuntimeDiagnostics.record(context, "info", "Подтверждена остановка VPN-сервиса.")
            scope.launch {
                if (_serviceState.value == SingboxConstants.STATE_STOPPED) disconnectCommandClient()
            }
        }
    }

    fun notifyAlert(message: String) {
        scope.launch { _alerts.emit(message) }
    }

}

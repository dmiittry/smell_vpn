package com.sme11.sme11_vpn

import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import dev.amirzr.singbox.service.RuntimeConnection
import dev.amirzr.singbox.service.RuntimeDiagnostics
import dev.amirzr.singbox.engine.SingboxManager

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var notificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sme11_vpn/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runtimeDiagnostics" -> executor.execute {
                        val events = RuntimeDiagnostics.snapshot(applicationContext)
                        val userStop = SingboxManager.getInstance(applicationContext).stopRequested
                        runOnUiThread { result.success(mapOf("events" to events, "userStop" to userStop)) }
                    }
                    "currentControl" -> result.success(RuntimeConnection.currentControl())
                    "requestNotifications" -> {
                        val preferences = getSharedPreferences("sme11_permissions", MODE_PRIVATE)
                        if (Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                        } else if (preferences.getBoolean("notification_asked", false)) {
                            result.success(false)
                        } else if (notificationResult != null) {
                            result.error("permission_busy", "Запрос разрешения уже открыт", null)
                        } else {
                            notificationResult = result
                            preferences.edit().putBoolean("notification_asked", true).apply()
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 901)
                        }
                    }
                    "notificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(null)
                    }
                    "listApps" -> executor.execute {
                        try {
                            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                            val apps = packageManager.queryIntentActivities(intent, 0)
                                .filter { it.activityInfo.packageName != packageName }
                                .distinctBy { it.activityInfo.packageName }
                                .map { mapOf("id" to it.activityInfo.packageName,
                                    "name" to it.loadLabel(packageManager).toString()) }
                                .sortedBy { it["name"]?.lowercase() }
                            runOnUiThread { result.success(apps) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("apps_unavailable", "Не удалось получить приложения", null) }
                        }
                    }
                    "validateApps" -> {
                        val packages = call.arguments as? List<*> ?: emptyList<String>()
                        val missing = packages.filterIsInstance<String>().filter { pkg ->
                            try { packageManager.getApplicationInfo(pkg, 0); false }
                            catch (error: PackageManager.NameNotFoundException) { true }
                        }
                        result.success(missing)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        notificationResult?.success(false)
        notificationResult = null
        executor.shutdown()
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 901) {
            notificationResult?.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            notificationResult = null
        }
    }
}

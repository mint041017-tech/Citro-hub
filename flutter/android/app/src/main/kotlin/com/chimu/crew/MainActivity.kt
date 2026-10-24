package com.chimu.crew

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ComponentCallbacks2
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var memoryChannel: MethodChannel? = null
    private var highRefreshRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chimu.crew/location").setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocation" -> requestLocation(result)
                else -> result.notImplemented()
            }
        }
        memoryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chimu.crew/memory")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chimu.crew/display").setMethodCallHandler { call, result ->
            when (call.method) {
                "setHighRefresh" -> {
                    highRefreshRequested = call.argument<Boolean>("on") ?: false
                    applyFrameRate()
                    result.success(true)
                }
                "maxRefreshRate" -> result.success(maxRefreshRate())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chimu.crew/timer").setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val label = call.argument<String>("label") ?: ""
                    val end = call.argument<Long>("end") ?: 0L
                    val ok = runCatching {
                        showTimerNotification(id, label, end)
                    }.getOrDefault(false)
                    result.success(ok)
                }
                "cancel" -> {
                    val id = call.argument<Int>("id") ?: 0
                    NotificationManagerCompat.from(this).cancel(id)
                    result.success(true)
                }
                "cancelAll" -> {
                    NotificationManagerCompat.from(this).cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chimu.crew/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstallPackages())
                "openInstallSettings" -> result.success(openInstallSettings())
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid", "安装包路径为空", null)
                    } else {
                        installApk(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstallPackages(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val intents = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        )
        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = try {
            File(path).canonicalFile
        } catch (_: Exception) {
            null
        }
        if (file == null || !file.isFile || file.length() <= 0L) {
            result.error("missing", "安装包不存在或已损坏", null)
            return
        }
        // 只允许安装 App 自己缓存目录里的文件，防止 Dart 侧传入任意路径。
        val allowed = listOf(cacheDir, filesDir).any { root ->
            val base = try {
                root.canonicalPath
            } catch (_: Exception) {
                root.path
            }
            file.path.startsWith(base + File.separator)
        }
        if (!allowed) {
            result.error("forbidden", "安装包路径无效", null)
            return
        }
        if (!canInstallPackages()) {
            openInstallSettings()
            result.success("permission")
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri("apk", uri)
            }
            startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.error("install", e.message ?: "无法打开系统安装程序", null)
        }
    }

    /* 计时进行中用自定义 RemoteViews：系统自带的时间戳/计时器字号太小，
       这里把倒计时放到 30sp 的位置持续走动，通知被划掉后仍由系统计时。 */
    private fun showTimerNotification(id: Int, label: String, endMillis: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        ensureTimerChannel()
        val views = RemoteViews(packageName, R.layout.citro_timer_notification)
        views.setTextViewText(R.id.citro_timer_label, label)
        // Chronometer 走 elapsedRealtime 时基：把「结束时刻」换算成
        // elapsedRealtime + 剩余毫秒，配合 countDown 才能显示正确的倒计时。
        val remaining = (endMillis - System.currentTimeMillis()).coerceAtLeast(0L)
        val base = SystemClock.elapsedRealtime() + remaining
        views.setChronometer(R.id.citro_timer_chronometer, base, null, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            views.setChronometerCountDown(R.id.citro_timer_chronometer, true)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, TIMER_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_chimu)
            .setCustomContentView(views)
            .setCustomBigContentView(views)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pending)
            .build()
        NotificationManagerCompat.from(this).notify(id, notification)
        return true
    }

    private fun ensureTimerChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(TIMER_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            TIMER_CHANNEL_ID,
            "Citro 提醒",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "烹饪计时与社区消息"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            memoryChannel?.invokeMethod("trim", level)
        }
    }

    override fun onResume() {
        super.onResume()
        // 从后台回来时窗口偏好可能被系统重置，重新申请一次。
        if (highRefreshRequested) applyFrameRate()
    }

    /**
     * 游戏页期间请求窗口首选刷新率 = 屏幕最高刷新率（通常是 120Hz），
     * 退出游戏恢复「无偏好」，让系统回到默认刷新策略省电。
     *
     * Window 本身没有 setFrameRate（那是 Surface 的 API），窗口级可用的
     * 公开入口是 preferredRefreshRate；它在 API 21+ 生效，Android 15/16
     * 的 LTPO 屏也会据此切换到高刷模式。
     */
    @Suppress("DEPRECATION")
    private fun applyFrameRate() {
        val w = window ?: return
        val rate = if (highRefreshRequested) maxRefreshRate() else 0f
        val attrs = w.attributes
        if (attrs.preferredRefreshRate == rate) return
        attrs.preferredRefreshRate = rate
        w.attributes = attrs
    }

    private fun maxRefreshRate(): Float {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return 0f
        return try {
            val d = display ?: return 0f
            // 只在「当前分辨率」内挑最高刷新率，避免切到低分辨率高刷模式。
            val current = d.mode
            var max = current.refreshRate
            for (mode in d.supportedModes) {
                if (mode.physicalWidth == current.physicalWidth &&
                    mode.physicalHeight == current.physicalHeight &&
                    mode.refreshRate > max
                ) {
                    max = mode.refreshRate
                }
            }
            max
        } catch (_: Throwable) {
            0f
        }
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun requestLocation(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "正在获取定位", null)
            return
        }
        if (!hasLocationPermission()) {
            pendingResult = result
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                REQUEST_LOCATION
            )
            return
        }
        resolveLocation(result)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_LOCATION) return
        val result = pendingResult ?: return
        pendingResult = null
        if (hasLocationPermission()) {
            resolveLocation(result)
        } else {
            result.error("denied", "定位权限未开启", null)
        }
    }

    private fun resolveLocation(result: MethodChannel.Result) {
        try {
            val manager = getSystemService(LOCATION_SERVICE) as LocationManager
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
            if (providers.isEmpty()) {
                result.error("disabled", "系统定位服务未开启", null)
                return
            }

            var best: Location? = null
            for (p in providers) {
                val l = runCatching { manager.getLastKnownLocation(p) }.getOrNull() ?: continue
                val previous = best
                if (previous == null || l.time > previous.time) best = l
            }
            val last = best
            if (last != null && System.currentTimeMillis() - last.time < 5 * 60 * 1000) {
                reply(result, last)
                return
            }

            val finished = AtomicBoolean(false)
            val handler = Handler(Looper.getMainLooper())
            val provider = providers.first()
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (finished.compareAndSet(false, true)) {
                        handler.removeCallbacksAndMessages(null)
                        runCatching { manager.removeUpdates(this) }
                        reply(result, location)
                    }
                }

                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            }
            runCatching { manager.requestSingleUpdate(provider, listener, Looper.getMainLooper()) }
                .onFailure {
                    result.error("unavailable", "无法请求定位", null)
                    return
                }
            handler.postDelayed({
                if (finished.compareAndSet(false, true)) {
                    runCatching { manager.removeUpdates(listener) }
                    val fallback = best
                    if (fallback != null) {
                        reply(result, fallback)
                    } else {
                        result.error("unavailable", "暂时无法获取定位", null)
                    }
                }
            }, 8000)
        } catch (e: SecurityException) {
            result.error("denied", "定位权限未开启", null)
        } catch (e: Exception) {
            result.error("unavailable", e.message ?: "定位失败", null)
        }
    }

    private fun reply(result: MethodChannel.Result, loc: Location) {
        val latitude = loc.latitude
        val longitude = loc.longitude
        Thread {
            var city = ""
            try {
                if (Geocoder.isPresent()) {
                    @Suppress("DEPRECATION")
                    val addresses = Geocoder(this, Locale.getDefault()).getFromLocation(latitude, longitude, 1)
                    val address = addresses?.firstOrNull()
                    city = address?.locality ?: address?.subAdminArea ?: address?.adminArea ?: ""
                }
            } catch (_: Exception) {
            }
            val payload = hashMapOf<String, Any>(
                "latitude" to latitude,
                "longitude" to longitude,
                "accuracy" to loc.accuracy,
                "city" to city
            )
            runOnUiThread { result.success(payload) }
        }.start()
    }

    companion object {
        private const val REQUEST_LOCATION = 4301
        private const val TIMER_CHANNEL_ID = "citro_reminders"
    }
}

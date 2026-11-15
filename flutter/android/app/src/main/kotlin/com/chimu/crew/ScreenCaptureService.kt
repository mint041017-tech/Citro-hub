package com.chimu.crew

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 屏幕共享前台服务。
 *
 * Android 14（targetSdk 34+）的硬性要求：开始 MediaProjection 之前，必须先起一个
 * `foregroundServiceType=mediaProjection` 的前台服务，否则 `createVirtualDisplay`
 * 会抛 SecurityException。这个服务只负责占住这个类型 + 给一条常驻通知，
 * 采集本身仍由 flutter_webrtc 完成。
 *
 * 调用顺序（Dart 侧保证）：
 *   用户授权（requestCapturePermission）→ [start] → getDisplayMedia
 */
class ScreenCaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 共享结束，弹幕悬浮窗没有存在意义，兜底摘掉（Dart 侧通常会先显式 hide）。
            DanmakuOverlay.hide(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        runCatching { startInForeground() }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        ensureChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_chimu)
            .setContentTitle("正在共享屏幕")
            .setContentText("Citro 正在共享你的屏幕，点通知可回到应用")
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(
                android.app.PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    },
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "屏幕共享",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "共享屏幕时保持前台"
                setSound(null, null)
                enableVibration(false)
            }
        )
    }

    companion object {
        const val CHANNEL_ID = "citro_screen_capture"
        const val NOTIFICATION_ID = 4701
        const val ACTION_STOP = "com.chimu.crew.action.STOP_SCREEN_CAPTURE"

        /** 开始共享前调用。失败不抛 —— 采集本身仍会尝试。 */
        fun start(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java)
            runCatching {
                ContextCompat.startForegroundService(context, intent)
            }
        }

        /** 停止共享后调用。 */
        fun stop(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP
            }
            // startService 在后台可能抛 IllegalStateException；
            // 这时服务要么已经停了，要么直接 stopService。
            val delivered = runCatching {
                context.startService(intent)
                true
            }.getOrDefault(false)
            if (!delivered) {
                runCatching { context.stopService(intent) }
            }
        }
    }
}

package com.easytech.easy_tech_flutter

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.os.Build

class Application : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // MUST match: AndroidManifest default_notification_channel_id, FCM payload channel_id, Flutter easy_tech_v2
            // Without this channel existing before first Flutter frame, FCM may not show notifications when app is killed.
            val channelV2 = NotificationChannel(
                "easy_tech_v2",
                "Easy Tech - إشعارات مهمة",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "إشعارات تطبيق Easy Tech للمهام والطلبات"
                enableLights(true)
                lightColor = Color.parseColor("#F5A623")
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channelV2)

            // Legacy channel (older builds) — keep so old installs don't break
            val channelLegacy = NotificationChannel(
                "easy_tech_high_importance",
                "Easy Tech Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "إشعارات تطبيق Easy Tech"
                enableLights(true)
                lightColor = Color.parseColor("#F5A623")
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channelLegacy)
        }
    }
}

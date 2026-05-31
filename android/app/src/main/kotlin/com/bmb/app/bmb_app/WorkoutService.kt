package com.bmb.app.bmb_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.widget.RemoteViews

class WorkoutService : Service() {

    companion object {
        const val CHANNEL_ID = "workout_channel"
        const val NOTIFICATION_ID = 1001
        var instance: WorkoutService? = null
            private set
    }

    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("训练中")
            .setContentText("准备开始训练")
            .setSmallIcon(android.R.drawable.ic_notification_clear_all)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "训练状态",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "显示当前训练状态"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    fun updateNotification(state: String, title: String, text: String, remainingSecs: Int, totalSecs: Int) {
        val notification = when (state) {
            "resting" -> buildRestingNotification(title, text, remainingSecs, totalSecs)
            else -> buildStandardNotification(state, title, text)
        }
        startForeground(NOTIFICATION_ID, notification)
    }

    fun stopWorkout() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildStandardNotification(state: String, title: String, text: String): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_notification_clear_all)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .build()
    }

    private fun buildRestingNotification(title: String, text: String, remainingSecs: Int, totalSecs: Int): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val views = RemoteViews(packageName, R.layout.notification_rest_timer).apply {
            val progress = if (totalSecs > 0) (remainingSecs * 100 / totalSecs) else 0
            setProgressBar(R.id.circular_progress, 100, progress, false)
            setTextViewText(R.id.timer_text, remainingSecs.toString())
            setTextViewText(R.id.rest_title, title)
            setTextViewText(R.id.rest_subtitle, text)
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setCustomBigContentView(views)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_notification_clear_all)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .build()
    }
}

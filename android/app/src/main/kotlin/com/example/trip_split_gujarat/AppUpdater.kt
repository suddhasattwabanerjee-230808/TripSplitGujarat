package com.example.trip_split_gujarat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.IntentCompat
import java.io.File
import kotlin.concurrent.thread

/**
 * Installs a downloaded update APK in place through PackageInstaller, so the
 * update needs no "Install?" screen (Android 12+ lets an app silently update
 * itself once it is the installer of record — i.e. from the second OTA update
 * on; the first one still asks once), then reopens the app on the new version.
 */
object AppUpdater {
    private const val PREFS = "app_updater"
    private const val KEY_RELAUNCH = "relaunch_after_update"
    private const val CHANNEL = "app_updates"
    private const val UPDATED_NOTIFICATION_ID = 0x0717

    private val main = Handler(Looper.getMainLooper())
    private var onFailure: ((String) -> Unit)? = null

    /**
     * Streams [apk] into an install session, reporting staging progress in
     * [0, 1] on the main thread, then commits it. On success the system kills
     * this process and [relaunch] runs in the new version, so only failures
     * come back through [failure].
     */
    fun install(context: Context, apk: File, progress: (Double) -> Unit, failure: (String) -> Unit) {
        onFailure = failure
        val app = context.applicationContext
        thread(name = "app-updater") {
            try {
                val installer = app.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(app.packageName)
                    setSize(apk.length())
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                    }
                }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    val total = apk.length().coerceAtLeast(1)
                    session.openWrite("base.apk", 0, apk.length()).use { out ->
                        apk.inputStream().use { input ->
                            val buffer = ByteArray(1 shl 16)
                            var written = 0L
                            var lastPercent = -1
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                out.write(buffer, 0, n)
                                written += n
                                val percent = (written * 100 / total).toInt()
                                if (percent != lastPercent) {
                                    lastPercent = percent
                                    session.setStagingProgress(percent / 100f)
                                    main.post { progress(percent / 100.0) }
                                }
                            }
                        }
                        session.fsync(out)
                    }
                    app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putBoolean(KEY_RELAUNCH, true).commit()
                    // Mutable: the installer fills in the status extras.
                    val status = PendingIntent.getBroadcast(
                        app, sessionId, Intent(app, UpdateStatusReceiver::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    )
                    session.commit(status.intentSender)
                }
            } catch (e: Exception) {
                fail(app, e.message ?: e.toString())
            }
        }
    }

    fun fail(context: Context, message: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_RELAUNCH).apply()
        main.post {
            onFailure?.invoke(message)
            onFailure = null
        }
    }

    /**
     * Opens the app after an update this class started (no-op otherwise, so a
     * manual or adb install doesn't pop the app open). Android 10+ may block
     * starting an activity from the background, so a "tap to open"
     * notification goes up first; MainActivity clears it as soon as it starts.
     */
    fun relaunch(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_RELAUNCH, false)) return
        prefs.edit().remove(KEY_RELAUNCH).commit()

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        showUpdatedNotification(context, launch)
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
            // The notification is the way back in.
        }
    }

    fun clearUpdatedNotification(context: Context) {
        NotificationManagerCompat.from(context).cancel(UPDATED_NOTIFICATION_ID)
    }

    private fun showUpdatedNotification(context: Context, launch: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "App updates", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val version = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_logo)
            .setColor(0xFFF08018.toInt())
            .setContentTitle("TripSplit updated" + (version?.let { " to $it" } ?: ""))
            .setContentText("Tap to open")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()
        try {
            NotificationManagerCompat.from(context).notify(UPDATED_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notification permission not granted.
        }
    }
}

/** Receives the install session's result (delivered to the new version on success). */
class UpdateStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // First update after a manual install: Android asks to confirm once.
                val confirm = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_INTENT, Intent::class.java)
                if (confirm == null) {
                    AppUpdater.fail(context, "Android didn't offer an install confirmation")
                    return
                }
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirm)
            }
            PackageInstaller.STATUS_SUCCESS -> AppUpdater.relaunch(context)
            PackageInstaller.STATUS_FAILURE_ABORTED -> AppUpdater.fail(context, "Update cancelled")
            else -> AppUpdater.fail(
                context,
                intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Install failed ($status)",
            )
        }
    }
}

/** Backup trigger for [AppUpdater.relaunch] in case the session result arrives before the new process can take it. */
class PackageReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) AppUpdater.relaunch(context)
    }
}

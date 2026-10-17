package com.example.trip_split_gujarat

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // We're open, so the "updated — tap to open" fallback is no longer needed.
        AppUpdater.clearUpdatedNotification(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/updater")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "Missing APK path", null)
                        return@setMethodCallHandler
                    }
                    // On success this process is replaced, so `result` only ever reports failure.
                    AppUpdater.install(
                        this,
                        File(path),
                        progress = { channel.invokeMethod("installProgress", it) },
                        failure = { result.error("install_failed", it, null) },
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}

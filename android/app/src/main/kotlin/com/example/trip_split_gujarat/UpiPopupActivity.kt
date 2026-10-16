package com.example.trip_split_gujarat

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Transparent window running only the `upiPopupMain` Dart entrypoint — the quick-add popup. */
class UpiPopupActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "upiPopupMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Opened from the "Add" action, which (unlike a tap on the body) doesn't auto-cancel.
        UpiNotifier.cancel(this, intent.getIntExtra(UpiNotifier.EXTRA_NOTIFICATION_ID, -1))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "getTransaction" -> result.success(
                    mapOf(
                        "amount" to intent.getDoubleExtra("amount", 0.0),
                        "payee" to intent.getStringExtra("payee"),
                        "time" to intent.getLongExtra("time", System.currentTimeMillis()),
                    ),
                )
                "close" -> {
                    result.success(null)
                    finish()
                }
                // After saving: bring up the full app on that trip's expense list.
                "openTrip" -> {
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                    if (launch != null) {
                        launch.addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        )
                        launch.putExtra(MainActivity.EXTRA_TRIP_ID, call.argument<Int>("id") ?: -1)
                        launch.putExtra(MainActivity.EXTRA_TRIP_NAME, call.argument<String>("name"))
                        startActivity(launch)
                    }
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }
}

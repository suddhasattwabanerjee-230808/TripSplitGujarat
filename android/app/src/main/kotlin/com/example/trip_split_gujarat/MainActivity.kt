package com.example.trip_split_gujarat

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_TRIP_ID = "open_trip_id"
        const val EXTRA_TRIP_NAME = "open_trip_name"
    }

    private var launchChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/launch").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takePendingTrip") result.success(takeTrip(intent)) else result.notImplemented()
            }
        }
    }

    // Already running (singleTop): the UPI popup reopened us to show a trip.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeTrip(intent)?.let { launchChannel?.invokeMethod("openTrip", it) }
    }

    /** The trip the UPI popup asked us to open, consumed so it isn't reopened on rotation/restart. */
    private fun takeTrip(intent: Intent?): Map<String, Any?>? {
        val id = intent?.getIntExtra(EXTRA_TRIP_ID, -1) ?: -1
        if (id == -1) return null
        val trip = mapOf("id" to id, "name" to intent?.getStringExtra(EXTRA_TRIP_NAME))
        intent?.removeExtra(EXTRA_TRIP_ID)
        return trip
    }
}

package com.example.trip_split_gujarat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // The Dart call waiting for a UPI app to return (one payment at a time).
    private var pendingUpiResult: MethodChannel.Result? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/upi_settings").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(UpiSettings.isEnabled(this))
                "setEnabled" -> {
                    UpiSettings.setEnabled(this, call.arguments as? Boolean ?: true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/upi_pay").setMethodCallHandler { call, result ->
            when (call.method) {
                // Opens the UPI app chooser; answers with the app's response string
                // ("txnId=...&Status=SUCCESS&..."), "" if it returned nothing, or an error.
                "pay" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("bad_args", "Missing UPI link", null)
                        return@setMethodCallHandler
                    }
                    pendingUpiResult?.error("cancelled", "Another payment was started", null)
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                    try {
                        pendingUpiResult = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(Intent.createChooser(intent, "Pay with"), UPI_REQUEST)
                    } catch (e: ActivityNotFoundException) {
                        pendingUpiResult = null
                        result.error("no_upi_app", "No UPI app is installed", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/ocr").setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "Missing image path", null)
                        return@setMethodCallHandler
                    }
                    ReceiptOcr.recognize(this, path) { text, error ->
                        if (text != null) result.success(text) else result.error("ocr_failed", error, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST) return
        val result = pendingUpiResult ?: return
        pendingUpiResult = null
        if (resultCode == Activity.RESULT_CANCELED && data == null) {
            result.success("")
        } else {
            result.success(data?.getStringExtra("response") ?: "")
        }
    }

    private companion object {
        const val UPI_REQUEST = 4201
    }
}

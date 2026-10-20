package com.example.trip_split_gujarat

import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Transparent window running only the `upiPopupMain` Dart entrypoint — the quick-add popup. */
class UpiPopupActivity : FlutterActivity() {
    private var roar: MediaPlayer? = null

    override fun getDartEntrypointFunctionName(): String = "upiPopupMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Opened from the "Add" action, which (unlike a tap on the body) doesn't auto-cancel.
        UpiNotifier.cancel(this, intent.getIntExtra(UpiNotifier.EXTRA_NOTIFICATION_ID, -1))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppSignature.register(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripsplit/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "getTransaction" -> result.success(
                    mapOf(
                        "amount" to intent.getDoubleExtra("amount", 0.0),
                        "payee" to intent.getStringExtra("payee"),
                        "time" to intent.getLongExtra("time", System.currentTimeMillis()),
                    ),
                )
                // The lion on the "Expense added" screen.
                "roar" -> {
                    playRoar()
                    result.success(null)
                }
                "close" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Plays as a notification sound, so it follows that volume and stays quiet on silent/vibrate. */
    private fun playRoar() {
        roar?.release()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val session = (getSystemService(AUDIO_SERVICE) as AudioManager).generateAudioSessionId()
        roar = MediaPlayer.create(this, R.raw.lion_roar, attributes, session)?.apply {
            setOnCompletionListener { player ->
                player.release()
                if (roar === player) roar = null
            }
            start()
        }
    }

    override fun onDestroy() {
        roar?.release()
        roar = null
        super.onDestroy()
    }
}

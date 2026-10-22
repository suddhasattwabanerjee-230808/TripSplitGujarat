package com.example.trip_split_gujarat

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Transparent window running only the `upiPopupMain` Dart entrypoint — the quick-add popup. */
class UpiPopupActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "upiPopupMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // The engine started when the alert went up (see UpiPopupEngine), so the
    // popup shows at once; without one (the app was closed since), a new one.
    override fun getCachedEngineId(): String? = UpiPopupEngine.ready()

    // A warmed-up engine ran its popup once: it goes with this window.
    override fun shouldDestroyEngineWithHost(): Boolean = true

    override fun onCreate(savedInstanceState: Bundle?) {
        // Opened from the "Add" action, which (unlike a tap on the body) doesn't auto-cancel.
        // Cancel before super.onCreate, which blocks while the Flutter engine starts.
        UpiNotifier.cancel(this, intent.getIntExtra(UpiNotifier.EXTRA_NOTIFICATION_ID, -1))
        super.onCreate(savedInstanceState)
        UpiPopupEngine.opened(this)
    }

    override fun onDestroy() {
        UpiPopupEngine.closed(this)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UpiPopupEngine.register(flutterEngine, this)
    }

    /** The engine this popup shows (FlutterActivity's own getter is protected). */
    fun engine(): FlutterEngine? = flutterEngine

    fun transaction(): Map<String, Any?> = mapOf(
        "amount" to intent.getDoubleExtra("amount", 0.0),
        "payee" to intent.getStringExtra("payee"),
        "time" to intent.getLongExtra("time", System.currentTimeMillis()),
    )
}

/**
 * The popup's Flutter engine, started as soon as a UPI alert goes up: "Add"
 * then only has to show it, instead of waiting seconds for Flutter, Firebase
 * and the trips to load. Its Dart side asks for the payment straight away and
 * gets it once the popup opens. One engine per popup; Ignore (or swiping the
 * alert away) frees it.
 */
object UpiPopupEngine {
    private const val ID = "upi_popup"
    private val main = Handler(Looper.getMainLooper())
    private var popup: UpiPopupActivity? = null
    // Payments asked for by an engine whose popup isn't open yet.
    private val waiting = mutableListOf<Pair<FlutterEngine, MethodChannel.Result>>()

    /** Starts the engine if there isn't one (from any thread). */
    fun prewarm(context: Context) {
        val app = context.applicationContext
        main.post {
            if (FlutterEngineCache.getInstance().contains(ID)) return@post
            try {
                val engine = FlutterEngine(app)
                register(engine, app)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(FlutterInjector.instance().flutterLoader().findAppBundlePath(), "upiPopupMain"),
                )
                FlutterEngineCache.getInstance().put(ID, engine)
            } catch (e: Exception) {
                // "Add" starts its own engine instead.
            }
        }
    }

    /** Frees the engine: the alert was ignored or swiped away (from any thread). */
    fun drop() {
        main.post {
            val engine = FlutterEngineCache.getInstance().get(ID) ?: return@post
            FlutterEngineCache.getInstance().remove(ID)
            waiting.removeAll { it.first === engine }
            engine.destroy()
        }
    }

    fun ready(): String? = ID.takeIf { FlutterEngineCache.getInstance().contains(ID) }

    /**
     * The popup is open with its engine: it now owns a warmed-up one (and
     * destroys it on close), and the payment that engine asked for is answered.
     */
    fun opened(activity: UpiPopupActivity) {
        popup = activity
        val engine = activity.engine() ?: return
        if (FlutterEngineCache.getInstance().get(ID) === engine) FlutterEngineCache.getInstance().remove(ID)
        val answered = waiting.filter { it.first === engine }
        waiting.removeAll(answered)
        answered.forEach { it.second.success(activity.transaction()) }
    }

    /** The open popup showing [engine], if any. */
    private fun popupOf(engine: FlutterEngine): UpiPopupActivity? = popup?.takeIf { it.engine() === engine }

    fun closed(activity: UpiPopupActivity) {
        if (popup === activity) popup = null
    }

    fun register(engine: FlutterEngine, context: Context) {
        AppSignature.register(engine, context)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tripsplit/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "getTransaction" -> {
                    val open = popupOf(engine)
                    if (open != null) result.success(open.transaction()) else waiting.add(engine to result)
                }
                "close" -> {
                    result.success(null)
                    popupOf(engine)?.finish()
                }
                else -> result.notImplemented()
            }
        }
    }
}

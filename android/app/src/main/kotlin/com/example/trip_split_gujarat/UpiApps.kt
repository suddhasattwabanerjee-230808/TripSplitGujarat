package com.example.trip_split_gujarat

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import java.io.ByteArrayOutputStream

/** The installed apps that take UPI payments, for "Pay with UPI" and "Scan their QR". */
object UpiApps {
    // Shown first when installed, in this order. These are also listed in the
    // manifest's <queries>, so they're seen even while their upi://pay handler
    // is switched off: Google Pay and PhonePe ship it as a disabled
    // activity-alias and only enable it once the app has been set up, and
    // Android's package visibility doesn't reliably match aliases.
    private val preferred = listOf(
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp", // BHIM
        "in.amazon.mShop.android.shopping",
        "com.dreamplug.androidapp", // CRED
        "money.super.payments",
        "com.naviapp",
        "com.mobikwik_new",
        "com.myairtelapp",
    )

    private const val GPAY = "com.google.android.apps.nbu.paisa.user"
    private const val PHONEPE = "com.phonepe.app"

    fun list(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        val infos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val apps = linkedMapOf<String, Map<String, Any>>()
        for (info in infos) {
            val pkg = info.activityInfo.packageName
            if (pkg == context.packageName || pkg in apps) continue
            apps[pkg] = entry(pkg, info.loadLabel(pm).toString(), info.loadIcon(pm), canPay = true)
        }
        // Known UPI apps that are installed but didn't answer the query.
        for (pkg in preferred) {
            if (pkg in apps || pm.getLaunchIntentForPackage(pkg) == null) continue
            val app = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (_: PackageManager.NameNotFoundException) {
                continue
            }
            apps[pkg] = entry(pkg, pm.getApplicationLabel(app).toString(), pm.getApplicationIcon(app), canPay = false)
        }
        return apps.values.sortedBy { app ->
            preferred.indexOf(app["package"] as String).let { i -> if (i < 0) preferred.size else i }
        }
    }

    private fun entry(pkg: String, label: String, icon: Drawable, canPay: Boolean) = mapOf(
        "package" to pkg,
        "label" to label,
        "icon" to png(icon),
        "canPay" to canPay,
    )

    /** Opens [pkg] on its home screen; false if it can't. */
    fun open(context: Context, pkg: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    /**
     * Opens [pkg] straight on its QR scanner where we know how (Google Pay,
     * PhonePe), else on its home screen. False if it can't be opened at all.
     */
    fun scan(context: Context, pkg: String): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(pkg)
        val scanner: Intent? = when (pkg) {
            // Google Pay's own "Scan any QR code" launcher shortcut, built by
            // Flutter's quick_actions plugin: the launch activity with
            // ACTION_RUN and the shortcut type in this extra.
            GPAY -> launch?.let {
                Intent(it)
                    .setAction(Intent.ACTION_RUN)
                    .putExtra("some unique action key", "QR_SCAN")
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            PHONEPE -> Intent(Intent.ACTION_VIEW, Uri.parse("phonepe://qrcode")).setPackage(PHONEPE)
            else -> null
        }
        for (intent in listOfNotNull(scanner, launch)) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // Try the next way in.
            }
        }
        return false
    }

    private fun png(icon: Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        icon.setBounds(0, 0, size, size)
        icon.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }
}

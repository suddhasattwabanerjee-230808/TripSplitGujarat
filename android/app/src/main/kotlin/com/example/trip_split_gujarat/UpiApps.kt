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

/** The installed apps that take UPI payments, for "Pay with UPI". */
object UpiApps {
    // Shown first when installed, in this order.
    private val preferred = listOf(
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp", // BHIM
    )

    fun list(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        val infos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        return infos
            .distinctBy { it.activityInfo.packageName }
            .sortedBy { preferred.indexOf(it.activityInfo.packageName).let { i -> if (i < 0) preferred.size else i } }
            .map {
                mapOf(
                    "package" to it.activityInfo.packageName,
                    "label" to it.loadLabel(pm).toString(),
                    "icon" to png(it.loadIcon(pm)),
                )
            }
    }

    /** Opens [pkg] on its home screen (to scan a QR there); false if it can't. */
    fun open(context: Context, pkg: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    private fun png(icon: Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        icon.setBounds(0, 0, size, size)
        icon.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }
}

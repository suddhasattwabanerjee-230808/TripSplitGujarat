package com.example.trip_split_gujarat

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * SHA-1 of the certificate this app is signed with, as uppercase hex without
 * colons: what Google's X-Android-Cert header expects, so Places search works
 * with an Android-restricted API key whichever key (debug or release) signed us.
 */
object AppSignature {
    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "tripsplit/signature").setMethodCallHandler { call, result ->
            when (call.method) {
                "sha1" -> result.success(sha1(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun sha1(context: Context): String? = try {
        val pm = context.packageManager
        val cert: Signature? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES).signatures?.firstOrNull()
        }
        cert?.let { sig -> MessageDigest.getInstance("SHA-1").digest(sig.toByteArray()).joinToString("") { "%02X".format(it) } }
    } catch (e: Exception) {
        null
    }
}

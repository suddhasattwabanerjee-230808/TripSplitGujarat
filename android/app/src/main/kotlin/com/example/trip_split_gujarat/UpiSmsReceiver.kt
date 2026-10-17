package com.example.trip_split_gujarat

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * The home screen's "UPI payment alerts" switch. Kept in native prefs (not Flutter's)
 * because the receiver below runs without a Flutter engine. Off keeps the SMS
 * permission but posts nothing, so switching back on needs no re-grant.
 */
object UpiSettings {
    private const val PREFS = "upi_settings"
    private const val KEY_ENABLED = "alerts_enabled"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }
}

/** Watches incoming SMS for bank UPI debit alerts and posts a "add to trip" notification. */
class UpiSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!UpiSettings.isEnabled(context)) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return
        // Banks send from alphanumeric sender IDs (e.g. "VM-HDFCBK"); personal numbers are all digits.
        val sender = messages.first().originatingAddress ?: return
        if (sender.none { it.isLetter() }) return
        val body = messages.joinToString("") { it.messageBody ?: "" }
        val txn = UpiParser.parse(body) ?: return
        UpiNotifier.show(context, txn, messages.first().timestampMillis)
    }
}

data class UpiTxn(val amount: Double, val payee: String?)

object UpiParser {
    private val ic = RegexOption.IGNORE_CASE
    private val amount = Regex("""(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""", ic)
    private val debitedBy = Regex("""debited\s+by\s+(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)""", ic)
    private val debitWords = Regex("""\b(debited|sent|paid|spent|debit|withdrawn)\b""", ic)
    private val skipWords = Regex(
        """\b(otp|one time password|received|refund(ed)?|reversed|failed|declined|collect request|will be debited|mandate)\b""",
        ic,
    )
    // Ordered most → least specific; the generic "to X" pattern last, since footers like
    // "SMS BLOCK to 9199…" would otherwise win.
    private val payees = listOf(
        Regex("""trf to\s+(.+?)\s+ref""", ic),
        Regex("""a/c of\s+(.+?)\s+(?:thru|via|on)\b""", ic),
        Regex(""";\s*([A-Za-z0-9.&\- ]{2,40}?)\s+credited""", ic),
        Regex("""upi/[^/\s]+/[^/\s]+/([^/\n]+)""", ic),
        Regex("""\bto\s+(?:vpa\s+)?([A-Za-z0-9.\-_@& ]{2,40}?)(?=\s+on\b|\s+ref|\s*\(|\.\s|\n|$)""", ic),
    )

    fun parse(body: String): UpiTxn? {
        if (!body.contains("upi", ignoreCase = true)) return null
        if (!debitWords.containsMatchIn(body) || skipWords.containsMatchIn(body)) return null
        val raw = (debitedBy.find(body) ?: amount.find(body))?.groupValues?.get(1) ?: return null
        val value = raw.replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val payee = payees.firstNotNullOfOrNull { regex -> regex.find(body)?.groupValues?.get(1)?.let(::cleanPayee) }
        return UpiTxn(value, payee)
    }

    private fun cleanPayee(raw: String): String? {
        val name = raw.substringBefore('@').trim()
        if (name.isEmpty() || name.startsWith("your", true) || name.contains("a/c", true) || name.none { it.isLetter() }) {
            return null
        }
        return name.take(30)
    }
}

object UpiNotifier {
    private const val CHANNEL = "upi_payments"
    const val EXTRA_NOTIFICATION_ID = "notification_id"

    fun cancel(context: Context, id: Int) {
        if (id != -1) NotificationManagerCompat.from(context).cancel(id)
    }

    fun show(context: Context, txn: UpiTxn, time: Long) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        if (Build.VERSION.SDK_INT >= 26) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "UPI payments", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Payments detected from your bank's SMS alerts"
                },
            )
        }
        val id = (time % Int.MAX_VALUE).toInt()
        val open = Intent(context, UpiPopupActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("amount", txn.amount)
            putExtra("payee", txn.payee)
            putExtra("time", time)
            putExtra(EXTRA_NOTIFICATION_ID, id)
        }
        val add = PendingIntent.getActivity(
            context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val ignore = PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, UpiIgnoreReceiver::class.java).putExtra(EXTRA_NOTIFICATION_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val amountText = if (txn.amount % 1.0 == 0.0) {
            String.format(Locale.US, "%,.0f", txn.amount)
        } else {
            String.format(Locale.US, "%,.2f", txn.amount)
        }
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_logo)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.ic_notification_large))
            .setColor(0xFFF08018.toInt())
            .setContentTitle("₹$amountText paid" + (txn.payee?.let { " to $it" } ?: ""))
            .setContentText("Add it to your Gujarat trip?")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setAutoCancel(true)
            .setContentIntent(add)
            .addAction(0, "Add", add)
            .addAction(0, "Ignore", ignore)
            .build()
        NotificationManagerCompat.from(context).notify(id, notification)
    }
}

/** "Ignore" action on the UPI notification — just dismisses it. */
class UpiIgnoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        UpiNotifier.cancel(context, intent.getIntExtra(UpiNotifier.EXTRA_NOTIFICATION_ID, -1))
    }
}

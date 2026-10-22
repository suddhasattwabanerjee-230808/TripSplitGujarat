package com.example.trip_split_gujarat

import android.app.Notification
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat

/**
 * UPI payment alerts without the bank's SMS: reads the notification GPay or
 * PhonePe posts for a payment made ("₹250 paid to Ravi") and handles it like
 * the SMS (a settle-up being waited for, else "add to trip"). Needs the user
 * to allow notification access; only the UPI apps below are looked at.
 */
class UpiNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in UpiAppParser.apps) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras ?: return
        val lines = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_TITLE),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT),
        ) + (extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.filterNotNull() ?: emptyList())
        val txn = UpiAppParser.parse(lines.joinToString("\n")) ?: return
        UpiAlert.handle(this, txn, sbn.postTime, UpiAlert.APP_NOTIFICATION)
    }

    // Android unbinds a listener after an app update or under memory pressure,
    // and doesn't always bring it back: ask for it straight away.
    override fun onListenerDisconnected() {
        rebind(this)
    }

    companion object {
        fun isAllowed(context: Context): Boolean =
            NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

        /** Reconnects the listener if access is allowed (a no-op while it's connected). */
        fun rebind(context: Context) {
            if (Build.VERSION.SDK_INT < 24 || !isAllowed(context)) return
            try {
                NotificationListenerService.requestRebind(ComponentName(context, UpiNotificationListener::class.java))
            } catch (e: Exception) {
                // Not allowed right now; the next app start tries again.
            }
        }

        /** Notification access for TripSplit (its own page where Android has one). */
        fun openSettings(context: Context): Boolean {
            val component = ComponentName(context, UpiNotificationListener::class.java)
            val intents = mutableListOf<Intent>()
            if (Build.VERSION.SDK_INT >= 30) {
                intents += Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
            }
            intents += Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            for (intent in intents) {
                try {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    return true
                } catch (e: ActivityNotFoundException) {
                    // Try the next one.
                }
            }
            return false
        }
    }
}

/** A UPI app's "payment made" notification, e.g. "₹250 paid to Ravi" or "Payment successful · ₹250 to Ravi". */
object UpiAppParser {
    val apps = setOf(
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp", // BHIM
    )

    private val ic = RegexOption.IGNORE_CASE
    private val amount = Regex("""(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""", ic)
    private val paidWords = Regex(
        """\b(paid|sent|debited|transferred|payment\s+(?:of|to|successful|completed|done))\b""",
        ic,
    )
    // Money coming in, requests, offers and payments not (yet) made.
    private val skipWords = Regex(
        """\b(paid you|sent you|received|receive|request|requested|requesting|collect|cashback|rewards?|""" +
            """offers?|scratch|won|refund(?:ed)?|reversed|failed|declined|pending|processing|reminder|due|""" +
            """will be|expir\w*|credited to you|added to)\b""",
        ic,
    )
    private val payee = Regex(
        """\bto\s+(?:vpa\s+)?([^\n,!]{2,40}?)(?=\s+(?:on|via|using|from|is|was|has|successfully|ref|upi)\b|[\n,!]|\.\s|\.$|$)""",
        ic,
    )

    fun parse(text: String): UpiTxn? {
        if (!paidWords.containsMatchIn(text) || skipWords.containsMatchIn(text)) return null
        val raw = amount.find(text)?.groupValues?.get(1) ?: return null
        val value = raw.replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val name = payee.find(text)?.groupValues?.get(1)?.let(UpiParser::cleanPayee)
        return UpiTxn(value, name)
    }
}

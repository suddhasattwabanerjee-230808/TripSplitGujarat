package com.example.trip_split_gujarat

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * UPI payments spotted on Google Pay's and PhonePe's own screens, for when
 * neither the bank's SMS nor the app's notification comes. While one of them
 * is open it reads the screen's text: a payment screen ("Pay", "Enter UPI
 * PIN") starts a watch, and the success screen that follows ("Payment
 * successful", "₹250", "Paid to Ravi") is handled like the SMS (a settle-up
 * being waited for, else "add to trip"). A success screen with no payment
 * screen before it (an old one opened from the history) is left alone.
 * Android only sends it those two apps' screens (res/xml/upi_screen_watcher.xml).
 */
class UpiScreenWatcher : AccessibilityService() {
    /** When a payment screen was last seen; 0 = not watching. */
    private var payingSince = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val root = rootInActiveWindow ?: return
        val app = root.packageName?.toString() ?: return
        if (app !in UpiScreenParser.apps) return
        val now = System.currentTimeMillis()
        // NPCI's UPI PIN screen, which every UPI app uses.
        if (event?.className?.toString()?.contains("npci", ignoreCase = true) == true) payingSince = now
        val lines = mutableListOf<String>()
        collect(root, lines, 0)
        val screen = lines.joinToString("\n")
        if (UpiScreenParser.isPaying(screen)) {
            payingSince = now
            return
        }
        val watching = (payingSince != 0L && now - payingSince < WATCH) || UpiSettle.isWaiting(this)
        if (!watching) return
        val paid = UpiScreenParser.parseSuccess(screen) ?: return
        payingSince = 0L
        if (paid.ref != null && !UpiScreenParser.firstTime(this, paid.ref)) return
        UpiAlert.handle(this, paid.txn, now)
    }

    override fun onInterrupt() {}

    /** Every text on screen, top to bottom. */
    private fun collect(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > 40 || out.size > 400) return
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty()) out += text
        val description = node.contentDescription?.toString()?.trim()
        if (!description.isNullOrEmpty() && description != text) out += description
        for (i in 0 until node.childCount) collect(node.getChild(i), out, depth + 1)
    }

    companion object {
        /** From the payment screen to its success screen: the PIN, the bank, a slow network. */
        private const val WATCH = 10 * 60 * 1000L

        fun isAllowed(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val me = ComponentName(context, UpiScreenWatcher::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        /** TripSplit's own Accessibility page where Android allows it, else the list. */
        fun openSettings(context: Context): Boolean {
            val me = ComponentName(context, UpiScreenWatcher::class.java)
            val intents = listOf(
                Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
                    .putExtra(Intent.EXTRA_COMPONENT_NAME, me.flattenToString()),
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
            )
            for (intent in intents) {
                try {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    return true
                } catch (e: Exception) {
                    // Not allowed or not there: try the next one.
                }
            }
            return false
        }
    }
}

data class UpiScreenPayment(val txn: UpiTxn, val ref: String?)

object UpiScreenParser {
    val apps = setOf("com.google.android.apps.nbu.paisa.user", "com.phonepe.app")

    private val opts = setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)

    // About to pay: the amount screen's button, or the UPI PIN.
    private val paying = Regex(
        """^(pay|pay now|proceed to pay|proceed|confirm and pay|pay securely)$|^pay\s*(?:₹|rs\.?)\s*[\d,]|upi pin|enter pin""",
        opts,
    )
    private val success = Regex(
        """\b(?:payment|transaction|transfer)\s+(?:successful|success|completed?|done)\b|""" +
            """\b(?:paid|sent)\s+successfully\b|\bsuccessfully\s+(?:paid|sent)\b|\bmoney\s+sent\b|""" +
            """^paid\s+to\b|^sent\s+to\b|^₹\s*[\d,]+(?:\.\d{1,2})?\s+paid\b""",
        opts,
    )
    private val failed = Regex(
        """\b(unsuccessful|failed|failure|declined|pending|processing|cancelled|canceled|reversed|refund(?:ed)?)\b""",
        opts,
    )
    private val amount = Regex("""(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)""", setOf(RegexOption.IGNORE_CASE))
    private val payee = Regex("""\b(?:paid|sent|payment)\s+to\s*\n?\s*([^\n]{2,40})""", opts)
    // Rows of the payment history, not one payment.
    private val historyRow = Regex("""^(?:paid|sent)\s+to\b|^received\s+from\b""", opts)
    private val ref = Regex("""\b(\d{12})\b""")

    fun isPaying(screen: String): Boolean = paying.containsMatchIn(screen) && !success.containsMatchIn(screen)

    fun parseSuccess(screen: String): UpiScreenPayment? {
        if (!success.containsMatchIn(screen) || failed.containsMatchIn(screen)) return null
        if (historyRow.findAll(screen).count() > 1) return null
        val raw = amount.find(screen)?.groupValues?.get(1) ?: return null
        val value = raw.replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val name = payee.find(screen)?.groupValues?.get(1)?.trim()
            ?.takeIf { amount.find(it) == null }
            ?.let(UpiParser::cleanPayee)
        return UpiScreenPayment(UpiTxn(value, name), ref.find(screen)?.groupValues?.get(1))
    }

    /** True the first time a UPI reference number is seen (the last 50 are kept). */
    fun firstTime(context: Context, ref: String): Boolean {
        val prefs = context.getSharedPreferences("upi_screen_refs", Context.MODE_PRIVATE)
        val seen = prefs.getString("refs", "")!!.split(',').filter { it.isNotEmpty() }
        if (ref in seen) return false
        prefs.edit().putString("refs", (seen + ref).takeLast(50).joinToString(",")).apply()
        return true
    }
}

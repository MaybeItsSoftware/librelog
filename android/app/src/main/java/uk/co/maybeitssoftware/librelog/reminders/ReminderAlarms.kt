package uk.co.maybeitssoftware.librelog.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.launch
import uk.co.maybeitssoftware.librelog.LibrelogApplication
import uk.co.maybeitssoftware.librelog.MainActivity
import uk.co.maybeitssoftware.librelog.R

/**
 * Sets the alarm behind each reminder and posts it when it goes off.
 *
 * An alarm with a ten-minute window, not an exact one: exact alarms need a
 * permission the user grants by hand (and Play only lets alarm-clock apps
 * have outright), and a nudge to write at 20:00 is no worse at 20:07. The
 * alarm wakes the receiver, which looks at the journal *then*, so a day
 * written since it was set stays quiet, and sets the next one.
 */
class ReminderAlarms(private val context: Context, val settings: ReminderSettings = ReminderSettings(context)) {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    /** Sets or clears every reminder's alarm from the settings and [today]. */
    fun schedule(today: JournalToday, now: LocalDateTime = LocalDateTime.now()) {
        for (r in Reminder.entries) {
            val at = ReminderPlan.next(r, settings.enabled(r), settings.time(r), now, today)
            if (at == null) {
                alarms.cancel(alarmIntent(r))
            } else {
                val millis = at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                alarms.setWindow(AlarmManager.RTC_WAKEUP, millis, WINDOW_MS, alarmIntent(r))
            }
        }
    }

    /** Whether notifications may be shown: asked for at runtime from Android 13. */
    val canNotify: Boolean
        get() = (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            ) && NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** Shows [r], if it still has something to say about [today]. */
    fun post(r: Reminder, today: JournalToday) {
        val (title, body) = ReminderPlan.content(r, today) ?: return
        if (!canNotify) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Daily writing reminders, on this day, and streak nudges"
            },
        )
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(r.ordinal + 1, notification)
    }

    private fun alarmIntent(r: Reminder): PendingIntent = PendingIntent.getBroadcast(
        context,
        r.ordinal + 1,
        Intent(context, ReminderReceiver::class.java).setAction("$ACTION.${r.id}").putExtra(EXTRA, r.id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        private const val CHANNEL = "reminders"
        private const val ACTION = "uk.co.maybeitssoftware.librelog.REMINDER"
        const val EXTRA = "reminder"
        private const val WINDOW_MS = 10 * 60_000L
    }
}

/** A reminder's alarm going off: post it if it's still wanted, then set the next. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminder = Reminder.from(intent.getStringExtra(ReminderAlarms.EXTRA)) ?: return
        val model = (context.applicationContext as LibrelogApplication).model
        val pending = goAsync()
        model.scope.launch {
            try {
                model.fireReminder(reminder)
            } finally {
                pending.finish()
            }
        }
    }
}

/** Alarms don't survive a restart, and a changed clock or zone moves them: set them again. */
class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in RESCHEDULE_ON) return
        val model = (context.applicationContext as LibrelogApplication).model
        val pending = goAsync()
        model.scope.launch {
            try {
                model.scheduleReminders()
            } finally {
                pending.finish()
            }
        }
    }

    private companion object {
        val RESCHEDULE_ON = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
        )
    }
}

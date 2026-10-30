package uk.co.maybeitssoftware.librelog.reminders

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * The three reminders (SPEC.md §13), as on the iPhone (apple/App/Reminders.swift):
 * a daily nudge to write, "on this day", and a streak nudge. Each is one
 * notification at a time of day, scheduled on this phone only.
 */
enum class Reminder(val id: String, val defaultHour: Int, val skipsOnceWritten: Boolean) {
    Daily("daily", 20, skipsOnceWritten = true),
    OnThisDay("onThisDay", 9, skipsOnceWritten = false),
    StreakNudge("streakNudge", 21, skipsOnceWritten = true),
    ;

    companion object {
        fun from(id: String?): Reminder? = entries.firstOrNull { it.id == id }
    }
}

/** What a reminder needs to know about the journal today. */
data class JournalToday(val hasEntriesToday: Boolean, val streak: Int, val onThisDayCount: Int)

/**
 * Which reminders are on, and when, kept on this device (like the iPhone's
 * UserDefaults, and under the same keys): a reminder is about this phone
 * buzzing, so it doesn't sync.
 */
class ReminderSettings(private val prefs: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences("reminders", Context.MODE_PRIVATE))

    fun enabled(r: Reminder): Boolean = prefs.getBoolean("reminders.${r.id}.enabled", false)

    fun time(r: Reminder): LocalTime = LocalTime.of(
        prefs.getInt("reminders.${r.id}.hour", r.defaultHour).coerceIn(0, 23),
        prefs.getInt("reminders.${r.id}.minute", 0).coerceIn(0, 59),
    )

    fun setEnabled(r: Reminder, on: Boolean) = prefs.edit { putBoolean("reminders.${r.id}.enabled", on) }

    fun setTime(r: Reminder, time: LocalTime) = prefs.edit {
        putInt("reminders.${r.id}.hour", time.hour)
        putInt("reminders.${r.id}.minute", time.minute)
    }
}

object ReminderPlan {
    /**
     * When [r] next goes off, or null when it's off. Today at its time if
     * that's still to come, unless it's one that skips a day already written;
     * otherwise tomorrow. Whether it should still speak is asked again when it
     * goes off ([content]), so tomorrow's is right however the day went.
     */
    fun next(r: Reminder, enabled: Boolean, time: LocalTime, now: LocalDateTime, today: JournalToday): LocalDateTime? {
        if (!enabled) return null
        val todayAt = now.toLocalDate().atTime(time)
        val skipToday = r.skipsOnceWritten && today.hasEntriesToday
        return if (todayAt > now && !skipToday) todayAt else todayAt.plusDays(1)
    }

    /**
     * The notification [r] shows when it goes off, or null to stay quiet: a
     * day already written needs no nudge, and with nothing from this day in
     * other years there's nothing to look back on.
     */
    fun content(r: Reminder, today: JournalToday): Pair<String, String>? = when (r) {
        Reminder.Daily ->
            if (today.hasEntriesToday) null else "Daily journal" to "Take a moment to write about your day."
        Reminder.StreakNudge -> when {
            today.hasEntriesToday -> null
            today.streak > 1 -> "Keep your streak alive" to
                "You're on a ${today.streak}-day streak. Write an entry today to keep it going!"
            else -> "Keep your streak alive" to "Don't break your momentum. Take a minute to write today."
        }
        Reminder.OnThisDay ->
            if (today.onThisDayCount == 0) null
            else "On this day" to "Look back at what you wrote on this day in previous years."
    }
}

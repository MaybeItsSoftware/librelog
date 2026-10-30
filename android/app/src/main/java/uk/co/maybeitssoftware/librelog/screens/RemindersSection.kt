package uk.co.maybeitssoftware.librelog.screens

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.launch
import uk.co.maybeitssoftware.librelog.AppModel
import uk.co.maybeitssoftware.librelog.calendar.OwnEventForm
import uk.co.maybeitssoftware.librelog.calendar.TimePickDialog
import uk.co.maybeitssoftware.librelog.reminders.Reminder
import uk.co.maybeitssoftware.librelog.ui.Radius
import uk.co.maybeitssoftware.librelog.ui.StatusBanner
import uk.co.maybeitssoftware.librelog.ui.ToggleRow
import uk.co.maybeitssoftware.librelog.ui.Typeface
import uk.co.maybeitssoftware.librelog.ui.pressable
import uk.co.maybeitssoftware.librelog.ui.tokens

/**
 * Settings → Reminders (docs/reminders.md): a daily reminder to write, "on
 * this day", and a streak nudge, each at a time of its own. All scheduled on
 * this phone; Android 13 and later ask for notifications when the first is
 * switched on. Mirrors apple/App/Screens/RemindersSection.swift.
 */
@Composable
fun RemindersSection(app: AppModel) {
    val t = tokens
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = app.reminders.settings
    // Held here as well as in SharedPreferences, which Compose can't watch.
    val enabled = remember { mutableStateMapOf<Reminder, Boolean>().apply { Reminder.entries.forEach { put(it, settings.enabled(it)) } } }
    val times = remember { mutableStateMapOf<Reminder, LocalTime>().apply { Reminder.entries.forEach { put(it, settings.time(it)) } } }
    var canNotify by remember { mutableStateOf(app.reminders.canNotify) }
    var waiting by remember { mutableStateOf<Reminder?>(null) }
    var picking by remember { mutableStateOf<Reminder?>(null) }

    fun turn(r: Reminder, on: Boolean) {
        settings.setEnabled(r, on)
        enabled[r] = on
        scope.launch { app.scheduleReminders() }
    }

    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        canNotify = app.reminders.canNotify
        waiting?.let { if (granted) turn(it, true) }
        waiting = null
    }

    Section("Reminders") {
        val anyOn = enabled.values.any { it }
        if (anyOn && !canNotify) {
            StatusBanner(
                "Notifications are off for LibreLog. Tap to turn them on in Settings.",
                t.warning,
                onClick = {
                    context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
                    )
                },
            )
        }
        for (r in Reminder.entries) {
            ToggleRow(
                label(r),
                enabled[r] == true,
                onChange = { on ->
                    if (on && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !app.reminders.canNotify) {
                        waiting = r
                        ask.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        turn(r, on)
                    }
                },
                detail = detail(r),
            )
            if (enabled[r] == true) {
                ReminderTimeRow(time(times.getValue(r), DateFormat.is24HourFormat(context))) { picking = r }
            }
        }
        Text(
            "Reminders skip days you've already written. They're set on this phone and never leave it.",
            style = Typeface.small.copy(fontSize = 12.sp),
            color = t.muted,
        )
    }

    picking?.let { r ->
        val current = times.getValue(r)
        TimePickDialog(label(r), OwnEventForm.hhmm(current.hour, current.minute), onDismiss = { picking = null }) { picked ->
            OwnEventForm.parts(picked)?.let { (h, m) ->
                val chosen = LocalTime.of(h, m)
                settings.setTime(r, chosen)
                times[r] = chosen
            }
            picking = null
            scope.launch { app.scheduleReminders() }
        }
    }
}

@Composable
private fun ReminderTimeRow(value: String, onPick: () -> Unit) {
    val t = tokens
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Time", style = Typeface.ui, color = t.muted, modifier = Modifier.weight(1f))
        Text(
            value,
            style = Typeface.mono(15),
            color = t.ink,
            modifier = Modifier
                .pressable(onClick = onPick)
                .border(1.dp, t.input, RoundedCornerShape(Radius.control))
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .semantics { contentDescription = "Time: $value" },
        )
    }
}

private fun label(r: Reminder): String = when (r) {
    Reminder.Daily -> "Daily reminder"
    Reminder.OnThisDay -> "On this day"
    Reminder.StreakNudge -> "Streak nudge"
}

private fun detail(r: Reminder): String = when (r) {
    Reminder.Daily -> "A nudge to write, unless you already have."
    Reminder.OnThisDay -> "On days you wrote in other years."
    Reminder.StreakNudge -> "Later on, if today is still empty."
}

private fun time(time: LocalTime, is24Hour: Boolean): String =
    if (is24Hour) OwnEventForm.hhmm(time.hour, time.minute)
    else DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(time)

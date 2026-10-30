package uk.co.maybeitssoftware.librelog

import java.time.LocalDateTime
import java.time.LocalTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uk.co.maybeitssoftware.librelog.reminders.JournalToday
import uk.co.maybeitssoftware.librelog.reminders.Reminder
import uk.co.maybeitssoftware.librelog.reminders.ReminderPlan

class ReminderPlanTest {
    private val morning = LocalDateTime.of(2026, 10, 30, 8, 0)
    private val night = LocalDateTime.of(2026, 10, 30, 22, 0)
    private val eight = LocalTime.of(20, 0)
    private val empty = JournalToday(hasEntriesToday = false, streak = 0, onThisDayCount = 0)
    private val written = JournalToday(hasEntriesToday = true, streak = 4, onThisDayCount = 2)

    @Test fun offIsNeverSet() = assertNull(ReminderPlan.next(Reminder.Daily, false, eight, morning, empty))

    @Test fun laterTodayWhenTheTimeIsStillToCome() =
        assertEquals(LocalDateTime.of(2026, 10, 30, 20, 0), ReminderPlan.next(Reminder.Daily, true, eight, morning, empty))

    @Test fun tomorrowOnceTheTimeHasGone() =
        assertEquals(LocalDateTime.of(2026, 10, 31, 20, 0), ReminderPlan.next(Reminder.Daily, true, eight, night, empty))

    @Test fun aWrittenDaySkipsToTomorrow() {
        assertEquals(LocalDateTime.of(2026, 10, 31, 20, 0), ReminderPlan.next(Reminder.Daily, true, eight, morning, written))
        assertEquals(LocalDateTime.of(2026, 10, 31, 20, 0), ReminderPlan.next(Reminder.StreakNudge, true, eight, morning, written))
    }

    @Test fun onThisDayGoesOffWhetherOrNotTodayIsWritten() =
        assertEquals(LocalDateTime.of(2026, 10, 30, 20, 0), ReminderPlan.next(Reminder.OnThisDay, true, eight, morning, written))

    /** A streak nudge whose evening passed with the app shut still comes tomorrow. */
    @Test fun aMissedStreakNudgeIsSetForTomorrow() =
        assertEquals(LocalDateTime.of(2026, 10, 31, 20, 0), ReminderPlan.next(Reminder.StreakNudge, true, eight, night, empty))

    @Test fun aWrittenDayStaysQuietWhenTheAlarmGoesOff() {
        assertNull(ReminderPlan.content(Reminder.Daily, written))
        assertNull(ReminderPlan.content(Reminder.StreakNudge, written))
        assertNotNull(ReminderPlan.content(Reminder.Daily, empty))
    }

    @Test fun theStreakNudgeCountsTheStreak() {
        val (_, body) = ReminderPlan.content(Reminder.StreakNudge, empty.copy(streak = 6))!!
        assertTrue(body, "6-day streak" in body)
        val (_, short) = ReminderPlan.content(Reminder.StreakNudge, empty.copy(streak = 1))!!
        assertTrue(short, "streak" !in short)
    }

    @Test fun onThisDayNeedsSomethingToLookBackOn() {
        assertNull(ReminderPlan.content(Reminder.OnThisDay, empty))
        assertNotNull(ReminderPlan.content(Reminder.OnThisDay, empty.copy(onThisDayCount = 1)))
    }
}

# Reminders

Settings → Reminders (SPEC.md §13) has three, each off until switched on and
each at a time of its own:

| Reminder | Default | Goes off |
|---|---|---|
| Daily reminder | 20:00 | unless today already has an entry |
| On this day | 09:00 | when other years have entries on this date |
| Streak nudge | 21:00 | unless today already has an entry; names the streak when it's over a day |

They're local notifications set on the device: nothing is sent from a server,
and the settings don't sync, since they're about which phone buzzes. They keep
the same keys on every platform (`reminders.<id>.enabled`, `.hour`, `.minute`).

## iPhone

`apple/App/Reminders.swift`. The notifications are set whenever the app opens,
writes or merges a pull, with their text fixed at that moment. So a day written
on another device after that still gets its reminder, and a streak nudge whose
evening goes by with the app shut isn't set again until the app next opens.

## Android

`android/app/src/main/java/.../reminders/`. Each reminder is an alarm with a
ten-minute window (`AlarmManager.setWindow`). It doesn't use an exact alarm,
which needs a permission the user grants by hand, and Play only gives it
outright to alarm-clock apps. When the alarm goes off, `ReminderReceiver` reads
the journal then: a day written since stays quiet, the streak is today's, and
the next alarm is set. So Android always holds the next one, even if the app
isn't opened. Alarms are set again after a restart, an app update or a change
of clock or time zone (`ReminderRescheduleReceiver`). Android 13 and later ask
for notification permission when the first reminder is switched on.

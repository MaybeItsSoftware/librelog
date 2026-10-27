import SwiftUI

/// Settings → Reminders (SPEC.md §13): daily writing reminders, "on this day",
/// and streak nudges. All scheduled locally on device.
struct RemindersSection: View {
    @Environment(AppModel.self) private var app
    @State private var showingDeniedAlert = false
    @State private var authorizationStatus: NotificationAuthStatus = .notDetermined

    var body: some View {
        let reminders = app.reminders
        Section {
            if authorizationStatus == .denied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warning)
                    Text("Notifications are disabled in System Settings.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muted)
                }
                .listRowBackground(Color.raised)
            }

            Toggle("Daily reminder", isOn: dailyBinding)
                .tint(Color.primary)
                .listRowBackground(Color.raised)

            if reminders.settings.dailyReminderEnabled {
                DatePicker("Time", selection: dailyTimeBinding, displayedComponents: .hourAndMinute)
                    .listRowBackground(Color.raised)
            }

            Toggle("On this day", isOn: onThisDayBinding)
                .tint(Color.primary)
                .listRowBackground(Color.raised)

            if reminders.settings.onThisDayEnabled {
                DatePicker("Time", selection: onThisDayTimeBinding, displayedComponents: .hourAndMinute)
                    .listRowBackground(Color.raised)
            }

            Toggle("Streak nudge", isOn: streakNudgeBinding)
                .tint(Color.primary)
                .listRowBackground(Color.raised)

            if reminders.settings.streakNudgeEnabled {
                DatePicker("Time", selection: streakNudgeTimeBinding, displayedComponents: .hourAndMinute)
                    .listRowBackground(Color.raised)
            }
        } header: {
            Text("Reminders").microLabel()
        } footer: {
            Text("Reminders skip automatically on days you've already written. Notifications never leave this device.")
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
        }
        .task {
            authorizationStatus = await reminders.authorizationStatus()
        }
        .alert("Notifications Disabled", isPresented: $showingDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Librelog needs permission to deliver reminders. Please enable notifications in System Settings.")
        }
    }

    private var dailyBinding: Binding<Bool> {
        Binding(
            get: { app.reminders.settings.dailyReminderEnabled },
            set: { enabled in
                handleToggle(enabled: enabled) {
                    app.reminders.settings.dailyReminderEnabled = $0
                }
            }
        )
    }

    private var dailyTimeBinding: Binding<Date> {
        timeBinding(
            hour: app.reminders.settings.dailyReminderHour,
            minute: app.reminders.settings.dailyReminderMinute
        ) { h, m in
            app.reminders.settings.dailyReminderHour = h
            app.reminders.settings.dailyReminderMinute = m
        }
    }

    private var onThisDayBinding: Binding<Bool> {
        Binding(
            get: { app.reminders.settings.onThisDayEnabled },
            set: { enabled in
                handleToggle(enabled: enabled) {
                    app.reminders.settings.onThisDayEnabled = $0
                }
            }
        )
    }

    private var onThisDayTimeBinding: Binding<Date> {
        timeBinding(
            hour: app.reminders.settings.onThisDayHour,
            minute: app.reminders.settings.onThisDayMinute
        ) { h, m in
            app.reminders.settings.onThisDayHour = h
            app.reminders.settings.onThisDayMinute = m
        }
    }

    private var streakNudgeBinding: Binding<Bool> {
        Binding(
            get: { app.reminders.settings.streakNudgeEnabled },
            set: { enabled in
                handleToggle(enabled: enabled) {
                    app.reminders.settings.streakNudgeEnabled = $0
                }
            }
        )
    }

    private var streakNudgeTimeBinding: Binding<Date> {
        timeBinding(
            hour: app.reminders.settings.streakNudgeHour,
            minute: app.reminders.settings.streakNudgeMinute
        ) { h, m in
            app.reminders.settings.streakNudgeHour = h
            app.reminders.settings.streakNudgeMinute = m
        }
    }

    private func handleToggle(enabled: Bool, update: @escaping (Bool) -> Void) {
        if enabled {
            Task {
                let status = await app.reminders.authorizationStatus()
                if status == .denied {
                    showingDeniedAlert = true
                    authorizationStatus = .denied
                    return
                }
                let granted = await app.reminders.requestAuthorization()
                authorizationStatus = await app.reminders.authorizationStatus()
                if granted {
                    update(true)
                    await app.reminders.scheduleAll()
                } else {
                    showingDeniedAlert = true
                }
            }
        } else {
            update(false)
            Task {
                await app.reminders.scheduleAll()
            }
        }
    }

    private func timeBinding(hour: Int, minute: Int, update: @escaping (Int, Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                update(comps.hour ?? hour, comps.minute ?? minute)
                Task {
                    await app.reminders.scheduleAll()
                }
            }
        )
    }
}

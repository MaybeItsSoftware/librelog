import Foundation
import Observation
import UserNotifications

public enum NotificationAuthStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

public enum NotificationIdentifier {
    public static let daily = "librelog.reminder.daily"
    public static let onThisDay = "librelog.reminder.onThisDay"
    public static let streakNudge = "librelog.reminder.streakNudge"
}

public protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> NotificationAuthStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

public final class SystemNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func authorizationStatus() async -> NotificationAuthStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        @unknown default: return .notDetermined
        }
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}

public struct RemindersSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var dailyReminderEnabled: Bool {
        get { defaults.bool(forKey: "reminders.daily.enabled") }
        set { defaults.set(newValue, forKey: "reminders.daily.enabled") }
    }

    public var dailyReminderHour: Int {
        get { defaults.object(forKey: "reminders.daily.hour") as? Int ?? 20 }
        set { defaults.set(newValue, forKey: "reminders.daily.hour") }
    }

    public var dailyReminderMinute: Int {
        get { defaults.object(forKey: "reminders.daily.minute") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "reminders.daily.minute") }
    }

    public var onThisDayEnabled: Bool {
        get { defaults.bool(forKey: "reminders.onThisDay.enabled") }
        set { defaults.set(newValue, forKey: "reminders.onThisDay.enabled") }
    }

    public var onThisDayHour: Int {
        get { defaults.object(forKey: "reminders.onThisDay.hour") as? Int ?? 9 }
        set { defaults.set(newValue, forKey: "reminders.onThisDay.hour") }
    }

    public var onThisDayMinute: Int {
        get { defaults.object(forKey: "reminders.onThisDay.minute") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "reminders.onThisDay.minute") }
    }

    public var streakNudgeEnabled: Bool {
        get { defaults.bool(forKey: "reminders.streakNudge.enabled") }
        set { defaults.set(newValue, forKey: "reminders.streakNudge.enabled") }
    }

    public var streakNudgeHour: Int {
        get { defaults.object(forKey: "reminders.streakNudge.hour") as? Int ?? 21 }
        set { defaults.set(newValue, forKey: "reminders.streakNudge.hour") }
    }

    public var streakNudgeMinute: Int {
        get { defaults.object(forKey: "reminders.streakNudge.minute") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "reminders.streakNudge.minute") }
    }
}

public struct PlannedNotification: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    public let targetDate: Date
    public let dateComponents: DateComponents

    public func makeRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}

public struct NotificationPlan: Sendable, Equatable {
    public let notificationsToAdd: [PlannedNotification]
    public let identifiersToRemove: [String]
}

public enum NotificationSchedulePlanner {
    public static func plan(
        settings: RemindersSettings,
        now: Date = Date(),
        calendar: Calendar = .current,
        hasEntriesToday: Bool,
        currentStreak: Int,
        onThisDayCount: Int
    ) -> NotificationPlan {
        var toAdd: [PlannedNotification] = []
        var toRemove: [String] = []

        // 1. Daily writing reminder: skip if already written today
        if !settings.dailyReminderEnabled {
            toRemove.append(NotificationIdentifier.daily)
        } else {
            let todayDaily = calendar.date(
                bySettingHour: settings.dailyReminderHour,
                minute: settings.dailyReminderMinute,
                second: 0,
                of: now
            ) ?? now

            let targetDate: Date
            if hasEntriesToday {
                // User already wrote today: skip today, schedule for tomorrow
                targetDate = calendar.date(byAdding: .day, value: 1, to: todayDaily) ?? todayDaily
            } else if todayDaily > now {
                // Reminder time is later today
                targetDate = todayDaily
            } else {
                // Reminder time has already passed today
                targetDate = calendar.date(byAdding: .day, value: 1, to: todayDaily) ?? todayDaily
            }

            let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            toAdd.append(PlannedNotification(
                identifier: NotificationIdentifier.daily,
                title: "Daily Journal",
                body: "Take a moment to write about your day.",
                targetDate: targetDate,
                dateComponents: dc
            ))
        }

        // 2. Streak nudge: opt-in, evening reminder if no entry written today
        if !settings.streakNudgeEnabled {
            toRemove.append(NotificationIdentifier.streakNudge)
        } else if hasEntriesToday {
            // Already written today: skip/cancel today's streak nudge
            toRemove.append(NotificationIdentifier.streakNudge)
        } else {
            let todayNudge = calendar.date(
                bySettingHour: settings.streakNudgeHour,
                minute: settings.streakNudgeMinute,
                second: 0,
                of: now
            ) ?? now

            if todayNudge > now {
                let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: todayNudge)
                let body: String
                if currentStreak > 1 {
                    body = "You're on a \(currentStreak)-day streak. Write an entry today to keep it going!"
                } else {
                    body = "Don't break your momentum. Take a minute to write today."
                }
                toAdd.append(PlannedNotification(
                    identifier: NotificationIdentifier.streakNudge,
                    title: "Keep your streak alive",
                    body: body,
                    targetDate: todayNudge,
                    dateComponents: dc
                ))
            } else {
                toRemove.append(NotificationIdentifier.streakNudge)
            }
        }

        // 3. "On this day" notification: opt-in morning notification
        if !settings.onThisDayEnabled {
            toRemove.append(NotificationIdentifier.onThisDay)
        } else {
            let todayOnThisDay = calendar.date(
                bySettingHour: settings.onThisDayHour,
                minute: settings.onThisDayMinute,
                second: 0,
                of: now
            ) ?? now

            let targetDate: Date
            if todayOnThisDay > now {
                targetDate = todayOnThisDay
            } else {
                targetDate = calendar.date(byAdding: .day, value: 1, to: todayOnThisDay) ?? todayOnThisDay
            }

            let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            let body = onThisDayCount > 0
                ? "Look back at what you wrote on this day in previous years."
                : "Look back at your memories on this day in previous years."
            toAdd.append(PlannedNotification(
                identifier: NotificationIdentifier.onThisDay,
                title: "On This Day",
                body: body,
                targetDate: targetDate,
                dateComponents: dc
            ))
        }

        return NotificationPlan(notificationsToAdd: toAdd, identifiersToRemove: toRemove)
    }
}

@MainActor
@Observable
public final class RemindersManager {
    public var settings: RemindersSettings
    public let center: NotificationCenterProtocol
    private var statusProvider: (@Sendable () async throws -> (hasEntriesToday: Bool, streak: Int, onThisDayCount: Int))?

    public init(settings: RemindersSettings = RemindersSettings(), center: NotificationCenterProtocol = SystemNotificationCenter()) {
        self.settings = settings
        self.center = center
    }

    public func setStatusProvider(_ provider: @escaping @Sendable () async throws -> (hasEntriesToday: Bool, streak: Int, onThisDayCount: Int)) {
        self.statusProvider = provider
    }

    public func authorizationStatus() async -> NotificationAuthStatus {
        await center.authorizationStatus()
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func scheduleAll() async {
        guard let provider = statusProvider else { return }
        do {
            let (hasEntries, streak, onThisDayCount) = try await provider()
            await schedule(hasEntriesToday: hasEntries, streak: streak, onThisDayCount: onThisDayCount)
        } catch {
            await schedule(hasEntriesToday: false, streak: 0, onThisDayCount: 0)
        }
    }

    public func schedule(
        hasEntriesToday: Bool,
        streak: Int,
        onThisDayCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: calendar,
            hasEntriesToday: hasEntriesToday,
            currentStreak: streak,
            onThisDayCount: onThisDayCount
        )

        if !plan.identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.identifiersToRemove)
        }

        for notification in plan.notificationsToAdd {
            let request = notification.makeRequest()
            try? await center.add(request)
        }
    }
}

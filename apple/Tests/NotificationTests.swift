import XCTest
import UserNotifications
@testable import Librelog

final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var status: NotificationAuthStatus = .notDetermined
    var requestAuthResult: Bool = true
    var requestAuthCalled = false
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthCalled = true
        if requestAuthResult {
            status = .authorized
        } else {
            status = .denied
        }
        return requestAuthResult
    }

    func authorizationStatus() async -> NotificationAuthStatus {
        status
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        addedRequests
    }
}

@MainActor
final class NotificationTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "uk.co.maybeitssoftware.librelog.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Preferences Tests

    func testRemindersSettingsDefaults() {
        let settings = RemindersSettings(defaults: testDefaults)
        XCTAssertFalse(settings.dailyReminderEnabled)
        XCTAssertEqual(settings.dailyReminderHour, 20)
        XCTAssertEqual(settings.dailyReminderMinute, 0)

        XCTAssertFalse(settings.streakNudgeEnabled)
        XCTAssertEqual(settings.streakNudgeHour, 21)
        XCTAssertEqual(settings.streakNudgeMinute, 0)

        XCTAssertFalse(settings.onThisDayEnabled)
        XCTAssertEqual(settings.onThisDayHour, 9)
        XCTAssertEqual(settings.onThisDayMinute, 0)
    }

    func testRemindersSettingsPersistence() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = true
        settings.dailyReminderHour = 19
        settings.dailyReminderMinute = 30

        settings.streakNudgeEnabled = true
        settings.streakNudgeHour = 22
        settings.streakNudgeMinute = 15

        settings.onThisDayEnabled = true
        settings.onThisDayHour = 8
        settings.onThisDayMinute = 45

        let reloaded = RemindersSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.dailyReminderEnabled)
        XCTAssertEqual(reloaded.dailyReminderHour, 19)
        XCTAssertEqual(reloaded.dailyReminderMinute, 30)

        XCTAssertTrue(reloaded.streakNudgeEnabled)
        XCTAssertEqual(reloaded.streakNudgeHour, 22)
        XCTAssertEqual(reloaded.streakNudgeMinute, 15)

        XCTAssertTrue(reloaded.onThisDayEnabled)
        XCTAssertEqual(reloaded.onThisDayHour, 8)
        XCTAssertEqual(reloaded.onThisDayMinute, 45)
    }

    // MARK: - Daily Reminder Scheduling & Skip Logic

    func testDailyReminderSkipsTodayWhenEntriesExist() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = true
        settings.dailyReminderHour = 20
        settings.dailyReminderMinute = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Today at 14:00 (before reminder time of 20:00)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 14
        comps.minute = 0
        comps.second = 0
        let now = cal.date(from: comps)!

        // When user has already written today:
        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: true,
            currentStreak: 1,
            onThisDayCount: 0
        )

        let daily = plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.daily }
        XCTAssertNotNil(daily)
        // Must be scheduled for tomorrow (day 28), NOT today (day 27)
        XCTAssertEqual(daily?.dateComponents.day, 28)
        XCTAssertEqual(daily?.dateComponents.month, 10)
        XCTAssertEqual(daily?.dateComponents.year, 2026)
        XCTAssertEqual(daily?.dateComponents.hour, 20)
        XCTAssertEqual(daily?.dateComponents.minute, 0)
    }

    func testDailyReminderSchedulesTodayWhenNoEntriesYetAndBeforeTime() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = true
        settings.dailyReminderHour = 20
        settings.dailyReminderMinute = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Today at 14:00 (before reminder time of 20:00)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 14
        comps.minute = 0
        comps.second = 0
        let now = cal.date(from: comps)!

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: false,
            currentStreak: 0,
            onThisDayCount: 0
        )

        let daily = plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.daily }
        XCTAssertNotNil(daily)
        // Must be scheduled for today (day 27) at 20:00
        XCTAssertEqual(daily?.dateComponents.day, 27)
        XCTAssertEqual(daily?.dateComponents.hour, 20)
        XCTAssertEqual(daily?.dateComponents.minute, 0)
    }

    func testDailyReminderSchedulesTomorrowWhenNoEntriesYetAndAfterTime() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = true
        settings.dailyReminderHour = 20
        settings.dailyReminderMinute = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Today at 21:00 (after reminder time of 20:00)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 21
        comps.minute = 0
        comps.second = 0
        let now = cal.date(from: comps)!

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: false,
            currentStreak: 0,
            onThisDayCount: 0
        )

        let daily = plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.daily }
        XCTAssertNotNil(daily)
        // Must be scheduled for tomorrow (day 28)
        XCTAssertEqual(daily?.dateComponents.day, 28)
        XCTAssertEqual(daily?.dateComponents.hour, 20)
        XCTAssertEqual(daily?.dateComponents.minute, 0)
    }

    func testDailyReminderRemovedWhenDisabled() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = false

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            hasEntriesToday: false,
            currentStreak: 0,
            onThisDayCount: 0
        )

        XCTAssertTrue(plan.identifiersToRemove.contains(NotificationIdentifier.daily))
        XCTAssertNil(plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.daily })
    }

    // MARK: - Streak Nudge Logic

    func testStreakNudgeSkippedWhenAlreadyWrittenToday() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.streakNudgeEnabled = true
        settings.streakNudgeHour = 21

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 18
        comps.minute = 0
        let now = cal.date(from: comps)!

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: true,
            currentStreak: 5,
            onThisDayCount: 0
        )

        XCTAssertTrue(plan.identifiersToRemove.contains(NotificationIdentifier.streakNudge))
        XCTAssertNil(plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.streakNudge })
    }

    func testStreakNudgeScheduledWhenNoEntriesTodayAndBeforeTime() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.streakNudgeEnabled = true
        settings.streakNudgeHour = 21
        settings.streakNudgeMinute = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 18
        comps.minute = 0
        let now = cal.date(from: comps)!

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: false,
            currentStreak: 5,
            onThisDayCount: 0
        )

        let nudge = plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.streakNudge }
        XCTAssertNotNil(nudge)
        XCTAssertEqual(nudge?.dateComponents.day, 27)
        XCTAssertEqual(nudge?.dateComponents.hour, 21)
        XCTAssertTrue(nudge?.body.contains("5-day streak") == true)
    }

    // MARK: - On This Day Logic

    func testOnThisDayScheduledForTodayWhenBeforeMorningTime() {
        var settings = RemindersSettings(defaults: testDefaults)
        settings.onThisDayEnabled = true
        settings.onThisDayHour = 9
        settings.onThisDayMinute = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        comps.hour = 7
        comps.minute = 0
        let now = cal.date(from: comps)!

        let plan = NotificationSchedulePlanner.plan(
            settings: settings,
            now: now,
            calendar: cal,
            hasEntriesToday: false,
            currentStreak: 0,
            onThisDayCount: 3
        )

        let onThisDay = plan.notificationsToAdd.first { $0.identifier == NotificationIdentifier.onThisDay }
        XCTAssertNotNil(onThisDay)
        XCTAssertEqual(onThisDay?.dateComponents.day, 27)
        XCTAssertEqual(onThisDay?.dateComponents.hour, 9)
    }

    // MARK: - RemindersManager with MockNotificationCenter

    func testRemindersManagerRequestsAuthorization() async {
        let mock = MockNotificationCenter()
        mock.requestAuthResult = true
        let manager = RemindersManager(settings: RemindersSettings(defaults: testDefaults), center: mock)

        let statusBefore = await manager.authorizationStatus()
        XCTAssertEqual(statusBefore, .notDetermined)

        let granted = await manager.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertTrue(mock.requestAuthCalled)

        let statusAfter = await manager.authorizationStatus()
        XCTAssertEqual(statusAfter, .authorized)
    }

    func testRemindersManagerSchedulesCorrectly() async {
        let mock = MockNotificationCenter()
        var settings = RemindersSettings(defaults: testDefaults)
        settings.dailyReminderEnabled = true
        settings.dailyReminderHour = 20
        settings.streakNudgeEnabled = false
        settings.onThisDayEnabled = false

        let manager = RemindersManager(settings: settings, center: mock)
        manager.setStatusProvider {
            (hasEntriesToday: true, streak: 3, onThisDayCount: 0)
        }

        await manager.scheduleAll()

        XCTAssertTrue(mock.removedIdentifiers.contains(NotificationIdentifier.streakNudge))
        XCTAssertTrue(mock.removedIdentifiers.contains(NotificationIdentifier.onThisDay))
        XCTAssertEqual(mock.addedRequests.count, 1)
        XCTAssertEqual(mock.addedRequests.first?.identifier, NotificationIdentifier.daily)
    }
}

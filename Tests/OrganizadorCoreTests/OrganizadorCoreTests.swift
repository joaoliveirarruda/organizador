import XCTest
@testable import OrganizadorCore

final class TimerEngineTests: XCTestCase {
    let english = UUID()
    let reading = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testStartThenStopReturnsSession() {
        var engine = TimerEngine()
        XCTAssertNil(engine.start(english, at: t0))
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.elapsed(at: t0.addingTimeInterval(90)), 90)

        let session = engine.stop(at: t0.addingTimeInterval(600))
        XCTAssertEqual(session?.activityID, english)
        XCTAssertEqual(session?.duration, 600)
        XCTAssertFalse(engine.isRunning)
    }

    func testSwitchingActivityClosesCurrentSession() {
        var engine = TimerEngine()
        engine.start(english, at: t0)
        let closed = engine.start(reading, at: t0.addingTimeInterval(300))
        XCTAssertEqual(closed?.activityID, english)
        XCTAssertEqual(closed?.duration, 300)
        XCTAssertEqual(engine.running?.activityID, reading)
        XCTAssertEqual(engine.running?.startedAt, t0.addingTimeInterval(300))
    }

    func testStartingSameActivityKeepsRunning() {
        var engine = TimerEngine()
        engine.start(english, at: t0)
        XCTAssertNil(engine.start(english, at: t0.addingTimeInterval(50)))
        XCTAssertEqual(engine.running?.startedAt, t0)
    }

    func testTooShortSessionIsDiscarded() {
        var engine = TimerEngine()
        engine.start(english, at: t0)
        XCTAssertNil(engine.stop(at: t0.addingTimeInterval(0.4)))
        XCTAssertFalse(engine.isRunning)
    }

    func testStopWithoutRunningReturnsNil() {
        var engine = TimerEngine()
        XCTAssertNil(engine.stop(at: t0))
    }
}

final class StatsTests: XCTestCase {
    let english = UUID()
    let reading = UUID()
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testRunningTimerCountsTowardTotal() {
        let sessions = [FocusSession(activityID: english, start: date(28, 9), end: date(28, 10))]
        let running = RunningTimer(activityID: reading, startedAt: date(28, 11))
        let spans = Stats.spans(sessions: sessions, running: running, now: date(28, 11, 30))
        let today = Stats.day(containing: date(28, 12), calendar: calendar)

        XCTAssertEqual(Stats.total(spans, in: today), 5400)
        XCTAssertEqual(Stats.total(spans, in: today, activityIDs: [reading]), 1800)
    }

    func testSessionAcrossMidnightIsSplitBetweenDays() {
        let spans = [TimeSpan(activityID: english, start: date(27, 23), end: date(28, 1))]
        let monday = Stats.day(containing: date(27, 12), calendar: calendar)
        let tuesday = Stats.day(containing: date(28, 12), calendar: calendar)

        XCTAssertEqual(Stats.total(spans, in: monday), 3600)
        XCTAssertEqual(Stats.total(spans, in: tuesday), 3600)
    }

    func testTotalsByActivity() {
        let spans = [
            TimeSpan(activityID: english, start: date(28, 9), end: date(28, 10)),
            TimeSpan(activityID: english, start: date(28, 14), end: date(28, 14, 30)),
            TimeSpan(activityID: reading, start: date(28, 20), end: date(28, 20, 15)),
        ]
        let totals = Stats.totalsByActivity(spans, in: Stats.day(containing: date(28, 0), calendar: calendar))
        XCTAssertEqual(totals[english], 5400)
        XCTAssertEqual(totals[reading], 900)
    }

    func testTimelineFractions() {
        let spans = [
            TimeSpan(activityID: reading, start: date(28, 18), end: date(28, 19)),
            TimeSpan(activityID: english, start: date(28, 6), end: date(28, 12)),
            TimeSpan(activityID: english, start: date(26, 6), end: date(26, 7)),
        ]
        let segments = Stats.timeline(spans, day: Stats.day(containing: date(28, 0), calendar: calendar))

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].activityID, english)
        XCTAssertEqual(segments[0].startFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(segments[0].endFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(segments[1].startFraction, 0.75, accuracy: 1e-9)
    }

    func testWeekContainingDate() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        // 2026-10-28 is a Wednesday.
        let week = Stats.week(containing: date(28, 12), calendar: sundayFirst)
        XCTAssertEqual(week.start, date(25, 0))
        XCTAssertEqual(week.end, date(25, 0).addingTimeInterval(7 * 86_400))
    }

    func testDailyTotalsSkipEmptyDays() {
        let spans = [
            TimeSpan(activityID: english, start: date(22, 9), end: date(22, 10)),
            TimeSpan(activityID: english, start: date(28, 9), end: date(28, 11)),
            TimeSpan(activityID: english, start: date(10, 9), end: date(10, 11)),
        ]
        let rows = Stats.dailyTotalsByActivity(spans, days: 7, endingOn: date(28, 15), calendar: calendar)

        XCTAssertEqual(rows.map(\.day), [date(22, 0), date(28, 0)])
        XCTAssertEqual(rows.map(\.seconds), [3600, 7200])
    }
}

final class GoalProgressTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testProgressAndRequiredPace() {
        let goal = Goal(title: "Inglês", targetHours: 10, startDate: t0, deadline: t0.addingTimeInterval(14 * 86_400))
        let study = Activity(name: "Estudar inglês", colorHex: "#2D98DA", goalID: goal.id)
        let other = Activity(name: "Leitura", colorHex: "#20BF6B")
        let spans = [
            TimeSpan(activityID: study.id, start: t0, end: t0.addingTimeInterval(4 * 3600)),
            TimeSpan(activityID: other.id, start: t0, end: t0.addingTimeInterval(3600)),
            // Before the goal started: not counted.
            TimeSpan(activityID: study.id, start: t0.addingTimeInterval(-7200), end: t0.addingTimeInterval(-3600)),
        ]
        let progress = GoalProgress.compute(for: goal, activities: [study, other], spans: spans, now: t0.addingTimeInterval(7 * 86_400))

        XCTAssertEqual(progress.loggedSeconds, 4 * 3600)
        XCTAssertEqual(progress.fraction!, 0.4, accuracy: 1e-9)
        // 6 h left with 1 week to go.
        XCTAssertEqual(progress.requiredSecondsPerWeek!, 6 * 3600, accuracy: 1e-6)
        XCTAssertFalse(progress.isOverdue)
        XCTAssertFalse(progress.isComplete)
    }

    func testOverdueGoal() {
        let goal = Goal(title: "Inglês", targetHours: 10, startDate: t0, deadline: t0.addingTimeInterval(86_400))
        let progress = GoalProgress.compute(for: goal, activities: [], spans: [], now: t0.addingTimeInterval(2 * 86_400))
        XCTAssertTrue(progress.isOverdue)
        XCTAssertNil(progress.requiredSecondsPerWeek)
    }

    func testGoalWithoutTarget() {
        let goal = Goal(title: "Ler mais", startDate: t0)
        let progress = GoalProgress.compute(for: goal, activities: [], spans: [], now: t0)
        XCTAssertNil(progress.fraction)
        XCTAssertNil(progress.targetSeconds)
    }
}

final class JSONStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JSONStore(url: url)

        XCTAssertEqual(try store.load(), .empty)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = Activity(name: "Estudo", colorHex: "#FF6B6B", createdAt: start)
        let data = AppData(
            activities: [activity],
            sessions: [FocusSession(activityID: activity.id, start: start, end: start.addingTimeInterval(1500))],
            running: RunningTimer(activityID: activity.id, startedAt: start.addingTimeInterval(3600)),
            preferences: Preferences(dailyTargetMinutes: 180, idlePauseMinutes: 5)
        )
        try store.save(data)
        XCTAssertEqual(try store.load(), data)
    }

    func testLoadsFileFromOlderVersionWithMissingKeys() throws {
        let json = #"{"activities":[],"sessions":[],"preferences":{"dailyTargetMinutes":120}}"#
        let data = try JSONStore.makeDecoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.goals, [])
        XCTAssertEqual(data.tasks, [])
        XCTAssertNil(data.running)
        XCTAssertEqual(data.preferences, Preferences(dailyTargetMinutes: 120, idlePauseMinutes: 10))
        XCTAssertEqual(data.schemaVersion, AppData.currentSchemaVersion)
    }
}

final class DurationFormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(DurationFormat.clock(0), "0:00:00")
        XCTAssertEqual(DurationFormat.clock(3723.9), "1:02:03")
        XCTAssertEqual(DurationFormat.clock(-5), "0:00:00")
    }

    func testShort() {
        XCTAssertEqual(DurationFormat.short(15 * 60), "15min")
        XCTAssertEqual(DurationFormat.short(3 * 3600), "3h")
        XCTAssertEqual(DurationFormat.short(3 * 3600 + 15 * 60 + 59), "3h 15min")
    }
}

final class TaskListsTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testTodayIncludesOverdueAndSortsByDueThenPriority() {
        let now = day(28, 15)
        let overdue = TaskItem(title: "Atrasada", dueDate: day(26))
        let todayLow = TaskItem(title: "Hoje baixa", dueDate: day(28), priority: .low)
        let todayHigh = TaskItem(title: "Hoje alta", dueDate: day(28), priority: .high)
        let tomorrow = TaskItem(title: "Amanhã", dueDate: day(29))
        let undated = TaskItem(title: "Sem data")
        let done = TaskItem(title: "Feita", dueDate: day(28), completedAt: day(28, 9))
        let all = [tomorrow, undated, todayLow, done, overdue, todayHigh]

        XCTAssertEqual(TaskLists.today(all, now: now, calendar: calendar).map(\.title), ["Atrasada", "Hoje alta", "Hoje baixa"])
        XCTAssertEqual(TaskLists.upcoming(all, now: now, calendar: calendar).map(\.title), ["Amanhã", "Sem data"])
        XCTAssertEqual(TaskLists.completed(all).map(\.title), ["Feita"])
    }

    func testOverdue() {
        let now = day(28, 15)
        XCTAssertTrue(TaskLists.isOverdue(TaskItem(title: "a", dueDate: day(27)), now: now, calendar: calendar))
        XCTAssertFalse(TaskLists.isOverdue(TaskItem(title: "b", dueDate: day(28)), now: now, calendar: calendar))
        XCTAssertFalse(TaskLists.isOverdue(TaskItem(title: "c", dueDate: day(27), completedAt: now), now: now, calendar: calendar))
        XCTAssertFalse(TaskLists.isOverdue(TaskItem(title: "d"), now: now, calendar: calendar))
    }

    func testCompletedNewestFirst() {
        let first = TaskItem(title: "primeira", completedAt: day(20))
        let second = TaskItem(title: "segunda", completedAt: day(25))
        XCTAssertEqual(TaskLists.completed([first, second]).map(\.title), ["segunda", "primeira"])
    }
}

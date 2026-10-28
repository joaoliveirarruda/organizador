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
        XCTAssertEqual(data.habits, [])
        XCTAssertEqual(data.habitChecks, [])
        XCTAssertEqual(data.transactions, [])
        XCTAssertEqual(data.financeCategories, [])
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

final class HabitTrackerTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testManualCheckMarksDayDone() {
        let habit = Habit(name: "Meditar", colorHex: "#20BF6B")
        let tracker = HabitTracker(checks: [HabitCheck(habitID: habit.id, day: date(28, 9))], spans: [], calendar: calendar)
        XCTAssertTrue(tracker.isDone(habit, on: date(28, 22)))
        XCTAssertFalse(tracker.isDone(habit, on: date(27, 12)))
    }

    func testTimerMarksDayDoneAfterEnoughMinutes() {
        let reading = UUID()
        let habit = Habit(name: "Ler 30 min", colorHex: "#2D98DA", autoActivityID: reading, autoMinutes: 30)
        let spans = [
            TimeSpan(activityID: reading, start: date(27, 20), end: date(27, 20, 20)),
            TimeSpan(activityID: reading, start: date(28, 8), end: date(28, 8, 15)),
            TimeSpan(activityID: reading, start: date(28, 21), end: date(28, 21, 15)),
        ]
        let tracker = HabitTracker(checks: [], spans: spans, calendar: calendar)
        XCTAssertFalse(tracker.isDone(habit, on: date(27)))
        XCTAssertTrue(tracker.isDone(habit, on: date(28)))
        XCTAssertTrue(tracker.isDoneByTimer(habit, on: date(28)))
    }

    func testStreakCountsUpToYesterdayWhenTodayIsOpen() {
        let habit = Habit(name: "Meditar", colorHex: "#20BF6B")
        let checks = [25, 26, 27].map { HabitCheck(habitID: habit.id, day: date($0)) }
        let tracker = HabitTracker(checks: checks, spans: [], calendar: calendar)
        XCTAssertEqual(tracker.currentStreak(habit, now: date(28, 10)), 3)

        let withToday = HabitTracker(checks: checks + [HabitCheck(habitID: habit.id, day: date(28))], spans: [], calendar: calendar)
        XCTAssertEqual(withToday.currentStreak(habit, now: date(28, 10)), 4)
    }

    func testStreakBreaksOnMissedDay() {
        let habit = Habit(name: "Meditar", colorHex: "#20BF6B")
        let checks = [24, 25, 27, 28].map { HabitCheck(habitID: habit.id, day: date($0)) }
        let tracker = HabitTracker(checks: checks, spans: [], calendar: calendar)
        XCTAssertEqual(tracker.currentStreak(habit, now: date(28, 10)), 2)
        XCTAssertEqual(tracker.currentStreak(habit, now: date(30, 10)), 0)
    }

    func testCompletionRate() {
        let habit = Habit(name: "Meditar", colorHex: "#20BF6B")
        let checks = [22, 24, 26, 28].map { HabitCheck(habitID: habit.id, day: date($0)) }
        let tracker = HabitTracker(checks: checks, spans: [], calendar: calendar)
        XCTAssertEqual(tracker.completionRate(habit, days: 7, now: date(28, 10)), 4.0 / 7.0, accuracy: 1e-9)
    }
}

final class ICalendarTests: XCTestCase {
    let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
    let utc = TimeZone(identifier: "UTC")!

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func feed(_ events: String...) -> String {
        (["BEGIN:VCALENDAR", "VERSION:2.0"] + events + ["END:VCALENDAR"]).joined(separator: "\r\n")
    }

    func window(_ fromDay: Int, _ toDay: Int, month: Int = 10) -> DateInterval {
        DateInterval(start: date(2026, month, fromDay, in: saoPaulo), end: date(2026, month, toDay, in: saoPaulo))
    }

    func testParsesTimesInUTCAndTZIDAndAllDay() {
        let text = feed(
            "BEGIN:VEVENT", "UID:a", "SUMMARY:Daily", "DTSTART:20261028T120000Z", "DTEND:20261028T121500Z", "END:VEVENT",
            "BEGIN:VEVENT", "UID:b", "SUMMARY:1:1", "DTSTART;TZID=America/Sao_Paulo:20261028T140000",
            "DTEND;TZID=America/Sao_Paulo:20261028T143000", "LOCATION:Sala 2", "END:VEVENT",
            "BEGIN:VEVENT", "UID:c", "SUMMARY:Feriado", "DTSTART;VALUE=DATE:20261102", "DTEND;VALUE=DATE:20261103", "END:VEVENT"
        )
        let events = ICSParser.parse(text, defaultTimeZone: saoPaulo)
        XCTAssertEqual(events.count, 3)

        XCTAssertEqual(events[0].start, date(2026, 10, 28, 12, in: utc))
        XCTAssertEqual(events[0].duration, 900)

        XCTAssertEqual(events[1].summary, "1:1")
        XCTAssertEqual(events[1].start, date(2026, 10, 28, 14, in: saoPaulo))
        XCTAssertEqual(events[1].location, "Sala 2")

        XCTAssertTrue(events[2].isAllDay)
        XCTAssertEqual(events[2].start, date(2026, 11, 2, in: saoPaulo))
        XCTAssertEqual(events[2].duration, 86_400)
    }

    func testUnfoldsLinesUnescapesTextAndSkipsAlarms() {
        let text = feed(
            "BEGIN:VEVENT", "UID:a", "SUMMARY:Planejamento\\, revisão",
            " e próximos passos", "DTSTART:20261028T120000Z", "DURATION:PT1H30M",
            "BEGIN:VALARM", "SUMMARY:Lembrete", "TRIGGER:-PT10M", "END:VALARM", "END:VEVENT"
        )
        let events = ICSParser.parse(text, defaultTimeZone: saoPaulo)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "Planejamento, revisãoe próximos passos")
        XCTAssertEqual(events[0].duration, 5400)
    }

    func testWeeklyRecurrenceWithByDayCountAndExdate() {
        let text = feed(
            "BEGIN:VEVENT", "UID:w", "SUMMARY:Standup",
            "DTSTART;TZID=America/Sao_Paulo:20261026T090000", "DTEND;TZID=America/Sao_Paulo:20261026T091500",
            "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6",
            "EXDATE;TZID=America/Sao_Paulo:20261028T090000", "END:VEVENT"
        )
        let occurrences = CalendarExpansion.occurrences(
            of: ICSParser.parse(text, defaultTimeZone: saoPaulo), in: DateInterval(start: date(2026, 10, 1, in: saoPaulo), end: date(2026, 11, 30, in: saoPaulo))
        )
        // Mon 26, (Wed 28 excluded), Fri 30, Mon 2, Wed 4, Fri 6 — COUNT includes the excluded one.
        XCTAssertEqual(occurrences.map(\.start), [
            date(2026, 10, 26, 9, in: saoPaulo), date(2026, 10, 30, 9, in: saoPaulo),
            date(2026, 11, 2, 9, in: saoPaulo), date(2026, 11, 4, 9, in: saoPaulo), date(2026, 11, 6, 9, in: saoPaulo),
        ])
        XCTAssertEqual(occurrences[0].end.timeIntervalSince(occurrences[0].start), 900)
    }

    func testEditedAndCancelledOccurrencesReplaceTheOriginal() {
        let text = feed(
            "BEGIN:VEVENT", "UID:d", "SUMMARY:Daily", "DTSTART:20261026T120000Z", "DTEND:20261026T121500Z",
            "RRULE:FREQ=DAILY;UNTIL=20261029T235959Z", "END:VEVENT",
            "BEGIN:VEVENT", "UID:d", "SUMMARY:Daily (mais tarde)", "RECURRENCE-ID:20261027T120000Z",
            "DTSTART:20261027T150000Z", "DTEND:20261027T151500Z", "END:VEVENT",
            "BEGIN:VEVENT", "UID:d", "SUMMARY:Daily", "RECURRENCE-ID:20261028T120000Z", "STATUS:CANCELLED",
            "DTSTART:20261028T120000Z", "DTEND:20261028T121500Z", "END:VEVENT"
        )
        let occurrences = CalendarExpansion.occurrences(of: ICSParser.parse(text, defaultTimeZone: saoPaulo), in: window(1, 31))
        XCTAssertEqual(occurrences.map(\.start), [
            date(2026, 10, 26, 12, in: utc), date(2026, 10, 27, 15, in: utc), date(2026, 10, 29, 12, in: utc),
        ])
        XCTAssertEqual(occurrences[1].title, "Daily (mais tarde)")
    }

    func testMonthlyRecurrences() {
        let text = feed(
            "BEGIN:VEVENT", "UID:m1", "SUMMARY:Fechamento", "DTSTART:20261031T120000Z", "DTEND:20261031T130000Z",
            "RRULE:FREQ=MONTHLY;COUNT=3", "END:VEVENT",
            "BEGIN:VEVENT", "UID:m2", "SUMMARY:Comitê", "DTSTART:20261013T120000Z", "DTEND:20261013T130000Z",
            "RRULE:FREQ=MONTHLY;BYDAY=2TU", "END:VEVENT"
        )
        let events = ICSParser.parse(text, defaultTimeZone: saoPaulo)
        let all = CalendarExpansion.occurrences(of: events, in: DateInterval(
            start: date(2026, 10, 1, in: utc), end: date(2027, 3, 1, in: utc)
        ))
        // The 31st skips months without a 31st.
        XCTAssertEqual(all.filter { $0.title == "Fechamento" }.map(\.start), [
            date(2026, 10, 31, 12, in: utc), date(2026, 12, 31, 12, in: utc), date(2027, 1, 31, 12, in: utc),
        ])
        // Second Tuesday of each month.
        XCTAssertEqual(all.filter { $0.title == "Comitê" }.map(\.start), [
            date(2026, 10, 13, 12, in: utc), date(2026, 11, 10, 12, in: utc), date(2026, 12, 8, 12, in: utc),
            date(2027, 1, 12, 12, in: utc), date(2027, 2, 9, 12, in: utc),
        ])
    }

    func testWindowOnlyReturnsOverlappingOccurrences() {
        let text = feed(
            "BEGIN:VEVENT", "UID:x", "SUMMARY:Semanal", "DTSTART:20260105T120000Z", "DTEND:20260105T130000Z",
            "RRULE:FREQ=WEEKLY", "END:VEVENT"
        )
        let occurrences = CalendarExpansion.occurrences(
            of: ICSParser.parse(text, defaultTimeZone: saoPaulo),
            in: DateInterval(start: date(2026, 10, 26, in: utc), end: date(2026, 11, 2, in: utc))
        )
        XCTAssertEqual(occurrences.map(\.start), [date(2026, 10, 26, 12, in: utc)])
    }

    func testDurationParsing() {
        XCTAssertEqual(ICSParser.parseDuration("PT1H30M"), 5400)
        XCTAssertEqual(ICSParser.parseDuration("P1D"), 86_400)
        XCTAssertEqual(ICSParser.parseDuration("P1W"), 604_800)
        XCTAssertNil(ICSParser.parseDuration("1H"))
    }
}

final class FinanceTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    func testMonthSummaryAndCategories() {
        let food = UUID()
        let all = [
            MoneyTransaction(date: day(10, 5), amountCents: 500_000, description: "Salário"),
            MoneyTransaction(date: day(10, 6), amountCents: -4_590, description: "Mercado", categoryID: food),
            MoneyTransaction(date: day(10, 20), amountCents: -1_000, description: "Padaria", categoryID: food),
            MoneyTransaction(date: day(10, 21), amountCents: -2_000, description: "Sem categoria"),
            MoneyTransaction(date: day(11, 1), amountCents: -9_999, description: "Mês seguinte", categoryID: food),
        ]
        let october = Finance.month(containing: day(10, 15), calendar: calendar)
        let summary = Finance.summary(all, in: october)

        XCTAssertEqual(summary.incomeCents, 500_000)
        XCTAssertEqual(summary.expenseCents, 7_590)
        XCTAssertEqual(summary.balanceCents, 492_410)
        XCTAssertEqual(summary.expenseByCategory[food], 5_590)
        XCTAssertEqual(summary.expenseByCategory[nil], 2_000)
        XCTAssertEqual(Finance.transactions(all, in: october).map(\.description), ["Sem categoria", "Padaria", "Mercado", "Salário"])
    }

    func testParseAmounts() {
        XCTAssertEqual(StatementImporter.parseAmountCents("-45,90"), -4_590)
        XCTAssertEqual(StatementImporter.parseAmountCents("R$ 1.234,56"), 123_456)
        XCTAssertEqual(StatementImporter.parseAmountCents("1,234.56"), 123_456)
        XCTAssertEqual(StatementImporter.parseAmountCents("-1.234"), -123_400)
        XCTAssertEqual(StatementImporter.parseAmountCents("12.5"), 1_250)
        XCTAssertEqual(StatementImporter.parseAmountCents("(12.00)"), -1_200)
        XCTAssertEqual(StatementImporter.parseAmountCents("800"), 80_000)
        XCTAssertNil(StatementImporter.parseAmountCents("abc"))
    }

    func testParsesSGMLOFXWithoutClosingTags() throws {
        let ofx = """
        OFXHEADER:100
        DATA:OFXSGML
        CHARSET:1252

        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
        <STMTTRN>
        <TRNTYPE>DEBIT
        <DTPOSTED>20261027120000[-3:BRT]
        <TRNAMT>-45.90
        <FITID>202610270001
        <MEMO>COMPRA CARTAO - PADARIA &amp; CAFE
        <STMTTRN>
        <TRNTYPE>CREDIT
        <DTPOSTED>20261028
        <TRNAMT>5000,00
        <FITID>202610280002
        <NAME>SALARIO
        </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """
        let lines = try StatementImporter.parse(ofx, calendar: calendar)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].date, day(10, 27))
        XCTAssertEqual(lines[0].amountCents, -4_590)
        XCTAssertEqual(lines[0].description, "COMPRA CARTAO - PADARIA & CAFE")
        XCTAssertEqual(lines[1].amountCents, 500_000)
        XCTAssertEqual(lines[1].description, "SALARIO")
        XCTAssertNotEqual(lines[0].key, lines[1].key)
    }

    func testParsesXMLOFXWithClosingTags() throws {
        let ofx = "<OFX><BANKTRANLIST><STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20261005</DTPOSTED>"
            + "<TRNAMT>-10.00</TRNAMT><FITID>A1</FITID><MEMO>Uber</MEMO></STMTTRN></BANKTRANLIST></OFX>"
        let lines = try StatementImporter.parse(ofx, calendar: calendar)
        XCTAssertEqual(lines.map(\.amountCents), [-1_000])
        XCTAssertEqual(lines.first?.description, "Uber")
    }

    func testParsesBrazilianCSV() throws {
        let csv = """
        Data;Descrição;Valor
        27/10/2026;"Mercado; Pão de Açúcar";-123,45
        27/10/2026;Café;-8,00
        27/10/2026;Café;-8,00
        linha inválida;;
        28/10/26;PIX recebido;"1.500,00"
        """
        let lines = try StatementImporter.parse(csv, calendar: calendar)
        XCTAssertEqual(lines.map(\.amountCents), [-12_345, -800, -800, 150_000])
        XCTAssertEqual(lines[0].description, "Mercado; Pão de Açúcar")
        XCTAssertEqual(lines[3].date, day(10, 28))
        // Two identical coffees on the same day are two different lines.
        XCTAssertNotEqual(lines[1].key, lines[2].key)
    }

    func testParsesNubankCardCSVWithInvertedSigns() throws {
        let csv = "date,title,amount\n2026-10-20,Spotify,21.90\n2026-10-21,Estorno,-21.90\n"
        let lines = try StatementImporter.parse(csv, invertSigns: true, calendar: calendar)
        XCTAssertEqual(lines.map(\.amountCents), [-2_190, 2_190])
        XCTAssertEqual(lines[0].date, day(10, 20))
    }

    func testCSVWithoutAmountColumnIsRejected() {
        XCTAssertThrowsError(try StatementImporter.parse("Nome;Idade\nJoão;30", calendar: calendar)) { error in
            XCTAssertEqual(error as? StatementImportError, .missingColumns)
        }
    }

    func testImportSkipsDuplicatesAndRemembersCategories() throws {
        let csv = "Data;Descrição;Valor\n27/10/2026;UBER *TRIP 123;-25,00\n28/10/2026;Café;-8,00\n"
        let transport = UUID()
        let first = try StatementImporter.parse(csv, calendar: calendar)
        let earlier = MoneyTransaction(date: day(9, 1), amountCents: -1_800, description: "Uber *Trip 999", categoryID: transport)

        let imported = StatementImporter.newTransactions(from: first, existing: [earlier])
        XCTAssertEqual(imported.transactions.count, 2)
        XCTAssertEqual(imported.duplicates, 0)
        XCTAssertEqual(imported.transactions[0].categoryID, transport)
        XCTAssertNil(imported.transactions[1].categoryID)

        let again = StatementImporter.newTransactions(from: first, existing: [earlier] + imported.transactions)
        XCTAssertEqual(again.transactions.count, 0)
        XCTAssertEqual(again.duplicates, 2)
    }
}

final class NotesTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func kinds(_ text: String) -> [MarkdownSpan.Kind] {
        MarkdownSpans.parse(text).map(\.kind).filter { $0 != .marker }
    }

    func testWikiLinkTargets() {
        let text = "Ver [[Inglês]], [[Plano#Semana 1]] e [[Leitura|livros]]. De novo [[inglês]]. Vazio [[ ]]."
        XCTAssertEqual(WikiLinks.targets(in: text), ["Inglês", "Plano", "Leitura"])
    }

    func testRewriteKeepsSectionAndAlias() {
        let text = "[[Plano]] [[plano#Meta|aqui]] [[Planos]]"
        XCTAssertEqual(WikiLinks.rewrite(text, from: "Plano", to: "Roteiro"), "[[Roteiro]] [[Roteiro#Meta|aqui]] [[Planos]]")
    }

    func testStoreCreatesRenamesAndRewritesLinks() throws {
        let store = NoteStore(folder: folder)
        let plan = try store.create(title: "Plano")
        let second = try store.create(title: "Plano")
        XCTAssertEqual(second.title, "Plano 2")
        var diary = try store.create(title: "Diário: dia/1")
        XCTAssertEqual(diary.title, "Diário- dia-1")
        diary.body = "Hoje segui o [[Plano|plano]]."
        try store.save(diary)

        let renamed = try store.rename(plan, to: "Roteiro")
        XCTAssertEqual(renamed.title, "Roteiro")
        XCTAssertThrowsError(try store.rename(renamed, to: "Plano 2")) { error in
            XCTAssertEqual(error as? NoteError, .alreadyExists("Plano 2"))
        }
        let notes = try store.list()
        XCTAssertEqual(Set(notes.map(\.title)), ["Roteiro", "Plano 2", "Diário- dia-1"])
        XCTAssertEqual(notes.first { $0.title == "Diário- dia-1" }?.body, "Hoje segui o [[Roteiro|plano]].")

        let caseOnly = try store.rename(renamed, to: "roteiro")
        XCTAssertEqual(try store.list().filter { $0.title.lowercased() == "roteiro" }.map(\.title), [caseOnly.title])
    }

    func testMarkdownBlocks() {
        let text = "# Título\n- [x] feito\n- [ ] fazer\n1. item\n> citação\n---\n```\n**não**\n```\n"
        XCTAssertEqual(kinds(text), [
            .heading(1), .checkbox(checked: true), .strikethrough, .checkbox(checked: false),
            .listItem, .quote, .rule, .codeBlock,
        ])
    }

    func testMarkdownInline() {
        let text = "**negrito** e *itálico* e `**código**` e [[Nota|apelido]] e [site](https://a.com)"
        let spans = MarkdownSpans.parse(text)
        XCTAssertEqual(spans.map(\.kind).filter { $0 != .marker }, [
            .code, .wikiLink("Nota"), .link("https://a.com"), .bold, .italic,
        ])
        let wiki = spans.first { $0.kind == .wikiLink("Nota") }!
        let hidden = spans.filter { $0.kind == .marker && NSIntersectionRange($0.range, wiki.range).length > 0 }
        XCTAssertEqual(hidden.map { (text as NSString).substring(with: $0.range) }, ["[[Nota|", "]]"])
    }

    func testGraphLinksNotesGoalsAndTasks() throws {
        let store = NoteStore(folder: folder)
        var a = try store.create(title: "A")
        _ = try store.create(title: "B")
        let ingles = try store.create(title: "Inglês")
        a.body = "[[B]] [[Inglês]] [[Ler 30 min]] [[Fantasma]] [[A]]"
        var b = try store.list().first { $0.title == "B" }!
        b.body = "Volta para [[A]]"
        let goal = Goal(title: "inglês")
        let task = TaskItem(title: "Ler 30 min")
        let notes = [a, b, ingles]

        let graph = NoteGraph.build(notes: notes, goals: [goal], tasks: [task])
        XCTAssertEqual(graph.nodes.map(\.title), ["A", "B", "Inglês", "Ler 30 min"])
        XCTAssertEqual(graph.nodes[3].ref, .task(task.id))
        XCTAssertEqual(graph.edges, [GraphEdge(from: 0, to: 1), GraphEdge(from: 0, to: 2), GraphEdge(from: 0, to: 3)])
        XCTAssertEqual(NoteGraph.backlinks(to: "b", in: notes).map(\.title), ["A"])
    }

    func testForceLayoutPullsLinkedNodesTogether() {
        var layout = ForceLayout(count: 4)
        let edges = [GraphEdge(from: 0, to: 1)]
        for _ in 0..<400 { layout.step(edges: edges) }
        func distance(_ i: Int, _ j: Int) -> Double {
            let d = layout.positions[i] - layout.positions[j]
            return (d * d).sum().squareRoot()
        }
        XCTAssertTrue(layout.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertLessThan(distance(0, 1), distance(2, 3))
        XCTAssertLessThan(layout.step(edges: edges), 1)
    }
}

final class SchemaV2Tests: XCTestCase {
    func testVersion1FileOpensWithNewDefaults() throws {
        let goalID = UUID()
        let json = """
        {"schemaVersion":1,
         "goals":[{"id":"\(goalID)","title":"CS229","startDate":"2026-10-01T00:00:00Z"}],
         "activities":[{"id":"\(UUID())","name":"Aulas","colorHex":"#2D98DA","goalID":"\(goalID)","isArchived":false,"createdAt":"2026-10-01T00:00:00Z"}],
         "sessions":[{"id":"\(UUID())","activityID":"\(UUID())","start":"2026-10-01T10:00:00Z","end":"2026-10-01T11:00:00Z"}],
         "preferences":{"dailyTargetMinutes":120}}
        """
        let data = try JSONStore.makeDecoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.schemaVersion, 2)
        let goal = try XCTUnwrap(data.goals.first)
        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(goal.staleDays, 7)
        XCTAssertNil(goal.weeklyHours)
        XCTAssertNil(goal.icon)
        XCTAssertNil(goal.cover)
        XCTAssertNil(data.activities.first?.icon)
        XCTAssertNil(data.sessions.first?.calendarEventID)
        XCTAssertFalse(data.preferences.exportSessionsToCalendar)
        XCTAssertEqual(data.preferences.exportCalendarID, "")
        XCTAssertTrue(data.preferences.staleGoalNotifications)
    }

    func testRoundTripWithNewFields() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = Goal(
            title: "OAB", startDate: start, icon: .emoji("⚖️"), cover: "capa.jpg",
            weeklyHours: 6, staleDays: 3, status: .paused
        )
        let area = Activity(name: "Penal", colorHex: "#FF6B6B", goalID: goal.id, createdAt: start, icon: .image("penal.png"), cover: "p.jpg")
        var session = FocusSession(activityID: area.id, start: start, end: start.addingTimeInterval(600))
        session.calendarEventID = "EV-1"
        var preferences = Preferences()
        preferences.exportSessionsToCalendar = true
        preferences.exportCalendarID = "CAL"
        preferences.staleGoalNotifications = false
        let data = AppData(activities: [area], goals: [goal], sessions: [session], preferences: preferences)

        let encoded = try JSONStore.makeEncoder().encode(data)
        XCTAssertEqual(try JSONStore.makeDecoder().decode(AppData.self, from: encoded), data)
    }
}

final class FrontMatterTests: XCTestCase {
    func testNoteWithoutBlock() {
        let (meta, body) = FrontMatter.parse("# Oi\n---\ntexto")
        XCTAssertEqual(meta, FrontMatter())
        XCTAssertEqual(body, "# Oi\n---\ntexto")
        XCTAssertEqual(meta.render(body), "# Oi\n---\ntexto")
    }

    func testReadsIconAndCoverAndKeepsUnknownKeys() {
        let text = "---\ntags:\n  - estudo\nicon: 📚\ncover: \"anexos/capa.jpg\"\naliases: [CS]\n---\nCorpo\n"
        let (meta, body) = FrontMatter.parse(text)
        XCTAssertEqual(meta.icon, .emoji("📚"))
        XCTAssertEqual(meta.cover, "anexos/capa.jpg")
        XCTAssertEqual(body, "Corpo\n")
        XCTAssertEqual(meta.render(body), "---\ntags:\n  - estudo\nicon: 📚\ncover: anexos/capa.jpg\naliases: [CS]\n---\nCorpo\n")
    }

    func testImageIcon() {
        XCTAssertEqual(FrontMatter.parse("---\nicon: anexos/eu.png\n---\n").0.icon, .image("anexos/eu.png"))
    }

    func testChangingIconPreservesBodyAndOtherKeys() {
        var (meta, body) = FrontMatter.parse("---\ntags: x\nicon: 📚\n---\nCorpo")
        meta.icon = .emoji("🧠")
        meta.cover = "anexos/c.png"
        XCTAssertEqual(meta.render(body), "---\ntags: x\nicon: 🧠\ncover: anexos/c.png\n---\nCorpo")
        meta.icon = nil
        meta.cover = nil
        XCTAssertEqual(meta.render(body), "---\ntags: x\n---\nCorpo")
        (meta, body) = FrontMatter.parse("Só corpo")
        meta.icon = .emoji("✅")
        XCTAssertEqual(meta.render(body), "---\nicon: ✅\n---\nSó corpo")
    }

    func testRoundTripIsLossless() {
        let text = "---\ntitle: \"A: B\"\nicon: 🎯\n---\n\n# Nota\n"
        let (meta, body) = FrontMatter.parse(text)
        XCTAssertEqual(meta.render(body), text)
    }
}

final class GoalThreadsTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    let folder = URL(fileURLWithPath: "/tmp/notas")

    /// October 2026; the 28th is a Wednesday.
    func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func note(_ title: String, _ body: String, modified: Date) -> Note {
        Note(url: folder.appendingPathComponent(title + ".md"), body: body, modifiedAt: modified)
    }

    func thread(_ goal: Goal, _ data: AppData, notes: [Note] = [], now: Date) -> GoalThread {
        var data = data
        if !data.goals.contains(where: { $0.id == goal.id }) { data.goals.append(goal) }
        return GoalThreads.compute(data: data, notes: notes, now: now, calendar: calendar).first { $0.goal.id == goal.id }!
    }

    func testNewGoalCountsFromItsStartDate() {
        let goal = Goal(title: "CS229", startDate: date(20))
        XCTAssertEqual(thread(goal, AppData(), now: date(26)).state, .active)
        let stalled = thread(goal, AppData(), now: date(27))
        XCTAssertEqual(stalled.state, .stalled)
        XCTAssertEqual(stalled.idleDays, 7)
        XCTAssertEqual(stalled.lastTouched, date(20))
    }

    func testSessionOnGoalAreaTouchesIt() {
        let goal = Goal(title: "CS229", startDate: date(1))
        let area = Activity(name: "Aulas", colorHex: "#000000", goalID: goal.id)
        let loose = Activity(name: "E-mails", colorHex: "#000000")
        let data = AppData(activities: [area, loose], sessions: [
            FocusSession(activityID: area.id, start: date(22, 9), end: date(22, 10)),
            FocusSession(activityID: loose.id, start: date(27, 9), end: date(27, 10)),
        ])
        let result = thread(goal, data, now: date(28))
        XCTAssertEqual(result.lastTouched, date(22, 10))
        XCTAssertEqual(result.idleDays, 6)
        XCTAssertEqual(result.state, .active)
        XCTAssertEqual(result.lastSession?.end, date(22, 10))
        XCTAssertEqual(thread(goal, data, now: date(29)).state, .stalled)
    }

    func testRunningTimerCountsAsTouchedNow() {
        let goal = Goal(title: "CS229", startDate: date(1))
        let area = Activity(name: "Aulas", colorHex: "#000000", goalID: goal.id)
        let data = AppData(activities: [area], running: RunningTimer(activityID: area.id, startedAt: date(28, 11)))
        let result = thread(goal, data, now: date(28, 12))
        XCTAssertEqual(result.lastTouched, date(28, 12))
        XCTAssertEqual(result.state, .active)
        XCTAssertEqual(result.weekSeconds, 3600)
    }

    func testLinkedNoteAndCompletedTaskTouchIt() {
        let goal = Goal(title: "CS229", startDate: date(1))
        let notes = [
            note("Aula 3", "Revisar [[cs229]] amanhã", modified: date(24)),
            note("Outra", "nada a ver", modified: date(27)),
        ]
        var result = thread(goal, AppData(), notes: notes, now: date(28))
        XCTAssertEqual(result.lastTouched, date(24))
        XCTAssertEqual(result.lastNote?.title, "Aula 3")

        let task = TaskItem(title: "Lista 1", goalID: goal.id, completedAt: date(26))
        result = thread(goal, AppData(tasks: [task]), notes: notes, now: date(28))
        XCTAssertEqual(result.lastTouched, date(26))
    }

    func testPausedAndClosedNeverStall() {
        for status in [GoalStatus.paused, .closed] {
            let goal = Goal(title: "CS229", startDate: date(1), status: status)
            let result = thread(goal, AppData(), now: date(28))
            XCTAssertEqual(result.state, status == .paused ? .paused : .closed)
        }
    }

    func testCustomLimit() {
        let goal = Goal(title: "Treino", startDate: date(25), staleDays: 2)
        XCTAssertEqual(thread(goal, AppData(), now: date(27)).state, .stalled)
    }

    func testWeekHoursAndIntendedPace() {
        let goal = Goal(title: "OAB", startDate: date(1), weeklyHours: 6)
        let area = Activity(name: "Penal", colorHex: "#000000", goalID: goal.id)
        let data = AppData(activities: [area], sessions: [
            FocusSession(activityID: area.id, start: date(25, 9), end: date(25, 11)),  // Sunday: last week
            FocusSession(activityID: area.id, start: date(26, 9), end: date(26, 11)),  // Monday
        ])
        let result = thread(goal, data, now: date(28))
        XCTAssertEqual(result.weekSeconds, 2 * 3600)
        XCTAssertEqual(result.weeklyTargetSeconds, 6 * 3600)
    }

    func testNextOpenTask() {
        let goal = Goal(title: "OAB", startDate: date(1))
        let tasks = [
            TaskItem(title: "Feita", goalID: goal.id, completedAt: date(20)),
            TaskItem(title: "Sem prazo", goalID: goal.id),
            TaskItem(title: "Amanhã", dueDate: date(29, 0), goalID: goal.id),
            TaskItem(title: "De outro", dueDate: date(28, 0)),
        ]
        XCTAssertEqual(thread(goal, AppData(tasks: tasks), now: date(28)).nextTask?.title, "Amanhã")
    }

    func testNoticeIsNilWithoutStalledGoals() {
        let goal = Goal(title: "CS229", startDate: date(27))
        let paused = Goal(title: "Piano", startDate: date(1), status: .paused)
        let threads = GoalThreads.compute(data: AppData(goals: [goal, paused]), notes: [], now: date(28), calendar: calendar)
        XCTAssertNil(GoalThreads.notice(threads))
    }

    func testNoticeJoinsStalledGoals() {
        let one = [Goal(title: "CS229", startDate: date(19))]
        var threads = GoalThreads.compute(data: AppData(goals: one), notes: [], now: date(28), calendar: calendar)
        XCTAssertEqual(GoalThreads.notice(threads), "CS229 está parado há 9 dias.")

        let goals = one + [Goal(title: "OAB", startDate: date(21)), Goal(title: "Inglês", startDate: date(10)), Goal(title: "Novo", startDate: date(28))]
        threads = GoalThreads.compute(data: AppData(goals: goals), notes: [], now: date(28), calendar: calendar)
        XCTAssertEqual(GoalThreads.notice(threads), "3 frentes paradas: Inglês (18 dias), CS229 (9 dias) e OAB (7 dias).")
    }
}

final class SessionEventTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testTitleWithGoal() {
        let goal = Goal(title: "Passar na OAB")
        let area = Activity(name: "Penal", colorHex: "#000000", goalID: goal.id)
        let session = FocusSession(activityID: area.id, start: start, end: start.addingTimeInterval(5400))
        let event = SessionEvent.make(session, area: area, goal: goal)
        XCTAssertEqual(event.title, "⏱ Penal · Passar na OAB")
        XCTAssertEqual(event.start, start)
        XCTAssertEqual(event.end, start.addingTimeInterval(5400))
    }

    func testTitleWithoutGoal() {
        let area = Activity(name: "E-mails", colorHex: "#000000")
        let session = FocusSession(activityID: area.id, start: start, end: start.addingTimeInterval(60))
        XCTAssertEqual(SessionEvent.make(session, area: area, goal: nil).title, "⏱ E-mails")
    }
}

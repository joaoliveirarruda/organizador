import Foundation

/// A daily habit. It is done on a day when checked by hand, or, if linked to an activity,
/// when the timer logged at least `autoMinutes` on that activity that day.
public struct Habit: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var autoActivityID: UUID?
    public var autoMinutes: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        autoActivityID: UUID? = nil,
        autoMinutes: Int = 30,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.autoActivityID = autoActivityID
        self.autoMinutes = autoMinutes
        self.createdAt = createdAt
    }
}

/// A manual check of a habit on one day.
public struct HabitCheck: Codable, Hashable, Sendable {
    public var habitID: UUID
    /// Start of the checked day.
    public var day: Date

    public init(habitID: UUID, day: Date) {
        self.habitID = habitID
        self.day = day
    }
}

/// Answers "was this habit done?" for any day, from manual checks and timed sessions.
public struct HabitTracker: Sendable {
    public let calendar: Calendar
    private let checkedDays: Set<HabitCheck>
    private let spans: [TimeSpan]

    public init(checks: [HabitCheck], spans: [TimeSpan], calendar: Calendar) {
        self.calendar = calendar
        self.checkedDays = Set(checks.map { HabitCheck(habitID: $0.habitID, day: calendar.startOfDay(for: $0.day)) })
        self.spans = spans
    }

    public func isChecked(_ habit: Habit, on day: Date) -> Bool {
        checkedDays.contains(HabitCheck(habitID: habit.id, day: calendar.startOfDay(for: day)))
    }

    /// Done by the timer: enough time on the linked activity that day.
    public func isDoneByTimer(_ habit: Habit, on day: Date) -> Bool {
        guard let activityID = habit.autoActivityID, habit.autoMinutes > 0 else { return false }
        let interval = Stats.day(containing: day, calendar: calendar)
        return Stats.total(spans, in: interval, activityIDs: [activityID]) >= TimeInterval(habit.autoMinutes * 60)
    }

    public func isDone(_ habit: Habit, on day: Date) -> Bool {
        isChecked(habit, on: day) || isDoneByTimer(habit, on: day)
    }

    /// Consecutive done days ending today. If today is not done yet, the streak counts up to
    /// yesterday, since the day is not over.
    public func currentStreak(_ habit: Habit, now: Date) -> Int {
        var day = calendar.startOfDay(for: now)
        if !isDone(habit, on: day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while isDone(habit, on: day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Share of the last `days` days (today included) on which the habit was done.
    public func completionRate(_ habit: Habit, days: Int, now: Date) -> Double {
        guard days > 0 else { return 0 }
        let today = calendar.startOfDay(for: now)
        let done = (0..<days).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return isDone(habit, on: day)
        }.count
        return Double(done) / Double(days)
    }
}

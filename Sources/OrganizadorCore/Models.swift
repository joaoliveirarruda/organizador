import Foundation

/// Something you spend time on, like "Estudar inglês". Sessions are logged against an activity.
public struct Activity: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// The goal this activity's time counts toward, if any.
    public var goalID: UUID?
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        goalID: UUID? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.goalID = goalID
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

/// A goal fed by the time logged on its activities, e.g. "100 h de inglês até 31/12".
public struct Goal: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var targetHours: Double?
    /// Only time logged on or after this date counts toward the goal.
    public var startDate: Date
    public var deadline: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        targetHours: Double? = nil,
        startDate: Date = Date(),
        deadline: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.targetHours = targetHours
        self.startDate = startDate
        self.deadline = deadline
    }
}

/// One continuous block of timed work. Pausing ends a session; resuming starts a new one.
public struct FocusSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var activityID: UUID
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), activityID: UUID, start: Date, end: Date) {
        self.id = id
        self.activityID = activityID
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// The timer currently running, persisted so it survives relaunching the app.
public struct RunningTimer: Codable, Hashable, Sendable {
    public var activityID: UUID
    public var startedAt: Date

    public init(activityID: UUID, startedAt: Date) {
        self.activityID = activityID
        self.startedAt = startedAt
    }
}

public struct Preferences: Codable, Hashable, Sendable {
    /// Daily focus target in minutes. 0 means no target.
    public var dailyTargetMinutes: Int
    /// Pause the timer after this many minutes without keyboard or mouse input. 0 disables it.
    public var idlePauseMinutes: Int
    /// Private iCal address of the calendar to show (Google Calendar's "secret address"). Empty when not set.
    public var calendarURL: String

    public init(dailyTargetMinutes: Int = 240, idlePauseMinutes: Int = 10, calendarURL: String = "") {
        self.dailyTargetMinutes = dailyTargetMinutes
        self.idlePauseMinutes = idlePauseMinutes
        self.calendarURL = calendarURL
    }

    private enum CodingKeys: String, CodingKey { case dailyTargetMinutes, idlePauseMinutes, calendarURL }

    // Missing keys fall back to defaults, so files from older versions keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        self.init(
            dailyTargetMinutes: try container.decodeIfPresent(Int.self, forKey: .dailyTargetMinutes)
                ?? defaults.dailyTargetMinutes,
            idlePauseMinutes: try container.decodeIfPresent(Int.self, forKey: .idlePauseMinutes)
                ?? defaults.idlePauseMinutes,
            calendarURL: try container.decodeIfPresent(String.self, forKey: .calendarURL) ?? defaults.calendarURL
        )
    }
}

/// Everything the app stores, saved as a single JSON file.
public struct AppData: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var activities: [Activity]
    public var goals: [Goal]
    public var sessions: [FocusSession]
    public var tasks: [TaskItem]
    public var habits: [Habit]
    public var habitChecks: [HabitCheck]
    public var financeCategories: [FinanceCategory]
    public var transactions: [MoneyTransaction]
    public var running: RunningTimer?
    public var preferences: Preferences

    public init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        activities: [Activity] = [],
        goals: [Goal] = [],
        sessions: [FocusSession] = [],
        tasks: [TaskItem] = [],
        habits: [Habit] = [],
        habitChecks: [HabitCheck] = [],
        financeCategories: [FinanceCategory] = [],
        transactions: [MoneyTransaction] = [],
        running: RunningTimer? = nil,
        preferences: Preferences = Preferences()
    ) {
        self.schemaVersion = schemaVersion
        self.activities = activities
        self.goals = goals
        self.sessions = sessions
        self.tasks = tasks
        self.habits = habits
        self.habitChecks = habitChecks
        self.financeCategories = financeCategories
        self.transactions = transactions
        self.running = running
        self.preferences = preferences
    }

    public static let empty = AppData()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, activities, goals, sessions, tasks, habits, habitChecks
        case financeCategories, transactions, running, preferences
    }

    // Missing keys fall back to defaults, so files from older versions keep loading
    // when new collections (tasks, habits, ...) are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? AppData.currentSchemaVersion,
            activities: try container.decodeIfPresent([Activity].self, forKey: .activities) ?? [],
            goals: try container.decodeIfPresent([Goal].self, forKey: .goals) ?? [],
            sessions: try container.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? [],
            tasks: try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? [],
            habits: try container.decodeIfPresent([Habit].self, forKey: .habits) ?? [],
            habitChecks: try container.decodeIfPresent([HabitCheck].self, forKey: .habitChecks) ?? [],
            financeCategories: try container.decodeIfPresent([FinanceCategory].self, forKey: .financeCategories) ?? [],
            transactions: try container.decodeIfPresent([MoneyTransaction].self, forKey: .transactions) ?? [],
            running: try container.decodeIfPresent(RunningTimer.self, forKey: .running),
            preferences: try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        )
    }
}

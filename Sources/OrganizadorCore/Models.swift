import Foundation

/// A small picture shown next to a name: an emoji, or an image file in the app's images folder.
public enum Icon: Codable, Hashable, Sendable {
    case emoji(String)
    /// File name inside the images folder.
    case image(String)

    private enum CodingKeys: String, CodingKey { case emoji, image }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) {
            self = .emoji(emoji)
        } else {
            self = .image(try container.decode(String.self, forKey: .image))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let emoji): try container.encode(emoji, forKey: .emoji)
        case .image(let file): try container.encode(file, forKey: .image)
        }
    }
}

/// An area (`Activity`) in the UI: something you spend time on, like "Estudar inglês". Sessions are logged against an activity.
public struct Activity: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// The goal this activity's time counts toward, if any.
    public var goalID: UUID?
    public var isArchived: Bool
    public var createdAt: Date
    public var icon: Icon?
    /// Image file name in the images folder, shown only on the area's own page.
    public var cover: String?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        goalID: UUID? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        icon: Icon? = nil,
        cover: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.goalID = goalID
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.icon = icon
        self.cover = cover
    }
}

public enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active, paused, closed
}

/// An objective (`Goal`) in the UI, fed by the time logged on its areas, e.g. "100 h de inglês até 31/12".
public struct Goal: Identifiable, Codable, Hashable, Sendable {
    public static let defaultStaleDays = 7

    public var id: UUID
    public var title: String
    public var targetHours: Double?
    /// Only time logged on or after this date counts toward the goal.
    public var startDate: Date
    public var deadline: Date?
    public var icon: Icon?
    /// Image file name in the images folder, shown only on the goal's own page.
    public var cover: String?
    /// Hours per week the user means to put in.
    public var weeklyHours: Double?
    /// Days without being touched before an active goal counts as stalled.
    public var staleDays: Int
    public var status: GoalStatus

    public init(
        id: UUID = UUID(),
        title: String,
        targetHours: Double? = nil,
        startDate: Date = Date(),
        deadline: Date? = nil,
        icon: Icon? = nil,
        cover: String? = nil,
        weeklyHours: Double? = nil,
        staleDays: Int = Goal.defaultStaleDays,
        status: GoalStatus = .active
    ) {
        self.id = id
        self.title = title
        self.targetHours = targetHours
        self.startDate = startDate
        self.deadline = deadline
        self.icon = icon
        self.cover = cover
        self.weeklyHours = weeklyHours
        self.staleDays = staleDays
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, targetHours, startDate, deadline, icon, cover, weeklyHours, staleDays, status
    }

    // Keys added in schema 2 fall back to defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            targetHours: try container.decodeIfPresent(Double.self, forKey: .targetHours),
            startDate: try container.decode(Date.self, forKey: .startDate),
            deadline: try container.decodeIfPresent(Date.self, forKey: .deadline),
            icon: try container.decodeIfPresent(Icon.self, forKey: .icon),
            cover: try container.decodeIfPresent(String.self, forKey: .cover),
            weeklyHours: try container.decodeIfPresent(Double.self, forKey: .weeklyHours),
            staleDays: try container.decodeIfPresent(Int.self, forKey: .staleDays) ?? Goal.defaultStaleDays,
            status: try container.decodeIfPresent(GoalStatus.self, forKey: .status) ?? .active
        )
    }
}

/// One continuous block of timed work. Pausing ends a session; resuming starts a new one.
public struct FocusSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var activityID: UUID
    public var start: Date
    public var end: Date
    /// Identifier of the event exported to the macOS Calendar, so it is updated instead of duplicated.
    public var calendarEventID: String?

    public init(id: UUID = UUID(), activityID: UUID, start: Date, end: Date, calendarEventID: String? = nil) {
        self.id = id
        self.activityID = activityID
        self.start = start
        self.end = end
        self.calendarEventID = calendarEventID
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
    /// Folder with the notes' `.md` files. Empty means the default folder next to the data file.
    public var notesFolderPath: String
    /// Turn every finished session into an event in the macOS Calendar.
    public var exportSessionsToCalendar: Bool
    /// EventKit identifier of the calendar the sessions go to. Empty means the default calendar.
    public var exportCalendarID: String
    /// At most one macOS notification a day listing the stalled goals.
    public var staleGoalNotifications: Bool

    public init(
        dailyTargetMinutes: Int = 240,
        idlePauseMinutes: Int = 10,
        calendarURL: String = "",
        notesFolderPath: String = "",
        exportSessionsToCalendar: Bool = false,
        exportCalendarID: String = "",
        staleGoalNotifications: Bool = true
    ) {
        self.dailyTargetMinutes = dailyTargetMinutes
        self.idlePauseMinutes = idlePauseMinutes
        self.calendarURL = calendarURL
        self.notesFolderPath = notesFolderPath
        self.exportSessionsToCalendar = exportSessionsToCalendar
        self.exportCalendarID = exportCalendarID
        self.staleGoalNotifications = staleGoalNotifications
    }

    private enum CodingKeys: String, CodingKey {
        case dailyTargetMinutes, idlePauseMinutes, calendarURL, notesFolderPath
        case exportSessionsToCalendar, exportCalendarID, staleGoalNotifications
    }

    // Missing keys fall back to defaults, so files from older versions keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        self.init(
            dailyTargetMinutes: try container.decodeIfPresent(Int.self, forKey: .dailyTargetMinutes)
                ?? defaults.dailyTargetMinutes,
            idlePauseMinutes: try container.decodeIfPresent(Int.self, forKey: .idlePauseMinutes)
                ?? defaults.idlePauseMinutes,
            calendarURL: try container.decodeIfPresent(String.self, forKey: .calendarURL) ?? defaults.calendarURL,
            notesFolderPath: try container.decodeIfPresent(String.self, forKey: .notesFolderPath)
                ?? defaults.notesFolderPath,
            exportSessionsToCalendar: try container.decodeIfPresent(Bool.self, forKey: .exportSessionsToCalendar)
                ?? defaults.exportSessionsToCalendar,
            exportCalendarID: try container.decodeIfPresent(String.self, forKey: .exportCalendarID)
                ?? defaults.exportCalendarID,
            staleGoalNotifications: try container.decodeIfPresent(Bool.self, forKey: .staleGoalNotifications)
                ?? defaults.staleGoalNotifications
        )
    }
}

/// Everything the app stores, saved as a single JSON file.
public struct AppData: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

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
            // Older files only lack keys that now have defaults, so they open as the current version.
            schemaVersion: max(
                try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AppData.currentSchemaVersion,
                AppData.currentSchemaVersion
            ),
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

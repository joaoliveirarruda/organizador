import Foundation

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A to-do. Named `TaskItem` to avoid clashing with Swift's `Task`.
public struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    /// Day the task is due (start of that day), if any.
    public var dueDate: Date?
    public var priority: TaskPriority
    public var goalID: UUID?
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .normal,
        goalID: UUID? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.goalID = goalID
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    public var isDone: Bool { completedAt != nil }
}

/// The three task lists: today (including overdue), upcoming (later or undated) and completed.
public enum TaskLists {
    public static func today(_ tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskItem] {
        let endOfToday = Stats.day(containing: now, calendar: calendar).end
        return sorted(tasks.filter { task in
            guard !task.isDone, let due = task.dueDate else { return false }
            return due < endOfToday
        })
    }

    public static func upcoming(_ tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskItem] {
        let endOfToday = Stats.day(containing: now, calendar: calendar).end
        return sorted(tasks.filter { task in
            guard !task.isDone else { return false }
            guard let due = task.dueDate else { return true }
            return due >= endOfToday
        })
    }

    /// Most recently completed first.
    public static func completed(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Not done and due before today.
    public static func isOverdue(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard !task.isDone, let due = task.dueDate else { return false }
        return due < calendar.startOfDay(for: now)
    }

    /// Earliest due date first (undated last), then higher priority, then oldest.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

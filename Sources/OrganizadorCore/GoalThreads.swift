import Foundation

/// A goal seen as a "frente": is it moving, stalled, or deliberately paused or closed?
public struct GoalThread: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case active, stalled, paused, closed
    }

    public var goal: Goal
    public var state: State
    /// Most recent of: a session ending on one of its areas (the running timer counts as now), a linked note
    /// edited, a linked task completed. Never earlier than the goal's start date.
    public var lastTouched: Date
    /// Whole days between `lastTouched` and now.
    public var idleDays: Int
    /// Time on the goal's areas this calendar week.
    public var weekSeconds: TimeInterval
    /// The intended weekly pace, if set.
    public var weeklyTargetSeconds: TimeInterval?
    // "Onde parei"
    public var lastSession: FocusSession?
    public var lastNote: Note?
    public var nextTask: TaskItem?
}

public enum GoalThreads {
    /// The state of every goal, in the order of `data.goals`. A note belongs to a goal when it links `[[Goal title]]`.
    public static func compute(data: AppData, notes: [Note], now: Date, calendar: Calendar) -> [GoalThread] {
        let spans = Stats.spans(sessions: data.sessions, running: data.running, now: now)
        let week = Stats.week(containing: now, calendar: calendar)
        return data.goals.map { goal in
            let areaIDs = Set(data.activities.filter { $0.goalID == goal.id }.map(\.id))
            let lastSession = data.sessions.filter { areaIDs.contains($0.activityID) }.max { $0.end < $1.end }
            let lastNote = NoteGraph.backlinks(to: goal.title, in: notes).max { $0.modifiedAt < $1.modifiedAt }
            let tasks = data.tasks.filter { $0.goalID == goal.id }

            var touches = [goal.startDate]
            touches += [lastSession?.end, lastNote?.modifiedAt].compactMap { $0 }
            touches += tasks.compactMap(\.completedAt)
            if let running = data.running, areaIDs.contains(running.activityID) { touches.append(now) }
            let lastTouched = touches.max()!

            let idleDays = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: lastTouched), to: calendar.startOfDay(for: now)
            ).day ?? 0
            let state: GoalThread.State = switch goal.status {
            case .paused: .paused
            case .closed: .closed
            case .active: idleDays >= goal.staleDays ? .stalled : .active
            }

            return GoalThread(
                goal: goal,
                state: state,
                lastTouched: lastTouched,
                idleDays: max(0, idleDays),
                weekSeconds: Stats.total(spans, in: week, activityIDs: areaIDs),
                weeklyTargetSeconds: goal.weeklyHours.map { $0 * 3600 },
                lastSession: lastSession,
                lastNote: lastNote,
                nextTask: TaskLists.sorted(tasks.filter { !$0.isDone }).first
            )
        }
    }

    /// The daily notification text joining every stalled goal, longest stalled first. Nil when none is stalled.
    public static func notice(_ threads: [GoalThread]) -> String? {
        let stalled = threads.filter { $0.state == .stalled }.sorted { $0.idleDays > $1.idleDays }
        guard let first = stalled.first else { return nil }
        if stalled.count == 1 {
            return "\(first.goal.title) está parado há \(days(first.idleDays))."
        }
        let items = stalled.map { "\($0.goal.title) (\(days($0.idleDays)))" }
        let list = items.dropLast().joined(separator: ", ") + " e " + items.last!
        return "\(stalled.count) frentes paradas: \(list)."
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? "1 dia" : "\(count) dias"
    }
}

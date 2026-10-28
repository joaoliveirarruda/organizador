import Foundation

/// Start/stop rules for the activity timer. Only one activity runs at a time:
/// starting another one closes the current session first.
public struct TimerEngine: Sendable {
    /// Sessions shorter than this (an accidental double click) are discarded.
    public static let minimumSessionDuration: TimeInterval = 1

    public private(set) var running: RunningTimer?

    public init(running: RunningTimer? = nil) {
        self.running = running
    }

    public var isRunning: Bool { running != nil }

    /// Starts timing `activityID`. Returns the session closed by switching activities, if any.
    @discardableResult
    public mutating func start(_ activityID: UUID, at date: Date) -> FocusSession? {
        if running?.activityID == activityID { return nil }
        let finished = stop(at: date)
        running = RunningTimer(activityID: activityID, startedAt: date)
        return finished
    }

    /// Stops the timer. Returns the finished session, or nil if nothing was running or it was too short.
    @discardableResult
    public mutating func stop(at date: Date) -> FocusSession? {
        guard let current = running else { return nil }
        running = nil
        let end = max(date, current.startedAt)
        guard end.timeIntervalSince(current.startedAt) >= Self.minimumSessionDuration else { return nil }
        return FocusSession(activityID: current.activityID, start: current.startedAt, end: end)
    }

    public func elapsed(at date: Date) -> TimeInterval {
        guard let running else { return 0 }
        return max(0, date.timeIntervalSince(running.startedAt))
    }
}

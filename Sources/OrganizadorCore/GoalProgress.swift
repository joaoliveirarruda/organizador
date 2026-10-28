import Foundation

public struct GoalProgress: Hashable, Sendable {
    public var loggedSeconds: TimeInterval
    public var targetSeconds: TimeInterval?
    /// Share of the target already logged, capped at 1. Nil when the goal has no hour target.
    public var fraction: Double?
    /// Hours per week still needed to hit the target by the deadline. Nil without both target and deadline.
    public var requiredSecondsPerWeek: TimeInterval?
    /// The deadline has passed and the target was not reached.
    public var isOverdue: Bool

    public var isComplete: Bool {
        guard let targetSeconds else { return false }
        return loggedSeconds >= targetSeconds
    }

    /// Progress of `goal`, counting time logged on its activities since the goal's start date.
    public static func compute(
        for goal: Goal,
        activities: [Activity],
        spans: [TimeSpan],
        now: Date
    ) -> GoalProgress {
        let activityIDs = Set(activities.filter { $0.goalID == goal.id }.map(\.id))
        let counted = DateInterval(start: goal.startDate, end: max(goal.startDate, now))
        let logged = Stats.total(spans, in: counted, activityIDs: activityIDs)

        guard let targetHours = goal.targetHours, targetHours > 0 else {
            return GoalProgress(
                loggedSeconds: logged, targetSeconds: nil, fraction: nil,
                requiredSecondsPerWeek: nil, isOverdue: false
            )
        }

        let target = targetHours * 3600
        let remaining = max(0, target - logged)
        var perWeek: TimeInterval?
        var overdue = false
        if let deadline = goal.deadline {
            let secondsLeft = deadline.timeIntervalSince(now)
            if remaining == 0 {
                perWeek = 0
            } else if secondsLeft <= 0 {
                overdue = true
            } else {
                perWeek = remaining / (secondsLeft / (7 * 86_400))
            }
        }

        return GoalProgress(
            loggedSeconds: logged,
            targetSeconds: target,
            fraction: min(1, logged / target),
            requiredSecondsPerWeek: perWeek,
            isOverdue: overdue
        )
    }
}

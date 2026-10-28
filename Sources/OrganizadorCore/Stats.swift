import Foundation

/// A span of time on one activity: a finished session, or the running timer up to now.
public struct TimeSpan: Hashable, Sendable {
    public var activityID: UUID
    public var start: Date
    public var end: Date

    public init(activityID: UUID, start: Date, end: Date) {
        self.activityID = activityID
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public enum Stats {
    public struct TimelineSegment: Hashable, Sendable {
        public var activityID: UUID
        /// Position within the day, from 0 (midnight) to 1 (next midnight).
        public var startFraction: Double
        public var endFraction: Double
    }

    public struct DailyActivityTotal: Hashable, Identifiable, Sendable {
        public var day: Date
        public var activityID: UUID
        public var seconds: TimeInterval

        public var id: String { "\(day.timeIntervalSince1970)-\(activityID.uuidString)" }
    }

    /// Finished sessions plus the running timer, as spans.
    public static func spans(sessions: [FocusSession], running: RunningTimer?, now: Date) -> [TimeSpan] {
        var result = sessions.map { TimeSpan(activityID: $0.activityID, start: $0.start, end: $0.end) }
        if let running, now > running.startedAt {
            result.append(TimeSpan(activityID: running.activityID, start: running.startedAt, end: now))
        }
        return result
    }

    public static func day(containing date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// The last `days` days ending with the day that contains `date`.
    public static func lastDays(_ days: Int, endingOn date: Date, calendar: Calendar) -> DateInterval {
        let today = day(containing: date, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today.start) ?? today.start
        return DateInterval(start: start, end: today.end)
    }

    /// How much of `span` falls inside `interval`. Sessions crossing midnight are split this way.
    public static func overlap(_ span: TimeSpan, _ interval: DateInterval) -> TimeInterval {
        let start = max(span.start, interval.start)
        let end = min(span.end, interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    public static func total(
        _ spans: [TimeSpan],
        in interval: DateInterval,
        activityIDs: Set<UUID>? = nil
    ) -> TimeInterval {
        spans.reduce(0) { sum, span in
            if let activityIDs, !activityIDs.contains(span.activityID) { return sum }
            return sum + overlap(span, interval)
        }
    }

    public static func totalsByActivity(_ spans: [TimeSpan], in interval: DateInterval) -> [UUID: TimeInterval] {
        var totals: [UUID: TimeInterval] = [:]
        for span in spans {
            let seconds = overlap(span, interval)
            if seconds > 0 { totals[span.activityID, default: 0] += seconds }
        }
        return totals
    }

    /// Colored blocks for a 24-hour bar, sorted by start.
    public static func timeline(_ spans: [TimeSpan], day: DateInterval) -> [TimelineSegment] {
        let length = day.duration
        guard length > 0 else { return [] }
        return spans
            .filter { overlap($0, day) > 0 }
            .sorted { $0.start < $1.start }
            .map { span in
                let start = max(span.start, day.start).timeIntervalSince(day.start)
                let end = min(span.end, day.end).timeIntervalSince(day.start)
                return TimelineSegment(
                    activityID: span.activityID,
                    startFraction: start / length,
                    endFraction: end / length
                )
            }
    }

    /// Time per activity for each of the last `days` days, oldest first. Days with no time are left out.
    public static func dailyTotalsByActivity(
        _ spans: [TimeSpan],
        days: Int,
        endingOn date: Date,
        calendar: Calendar
    ) -> [DailyActivityTotal] {
        let range = lastDays(days, endingOn: date, calendar: calendar)
        var result: [DailyActivityTotal] = []
        var dayStart = range.start
        while dayStart < range.end {
            let interval = day(containing: dayStart, calendar: calendar)
            let totals = totalsByActivity(spans, in: interval)
            for (activityID, seconds) in totals.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                result.append(DailyActivityTotal(day: interval.start, activityID: activityID, seconds: seconds))
            }
            dayStart = interval.end
        }
        return result
    }
}

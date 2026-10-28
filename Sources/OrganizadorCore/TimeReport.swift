import Foundation

public enum ReportPeriod: String, CaseIterable, Sendable {
    case week = "Semana"
    case month = "Mês"
    case year = "Ano"
    case total = "Total"
}

/// Time per area and, inside each, per activity over a period. Read-only summary for the report screen.
public enum TimeReport {
    public struct ActivityTotal: Hashable, Sendable {
        public var activity: Activity
        public var seconds: TimeInterval
    }

    public struct AreaTotal: Hashable, Sendable {
        /// `nil` groups activities without an area ("Sem área").
        public var area: Area?
        public var seconds: TimeInterval
        public var activities: [ActivityTotal]
    }

    /// The period containing `now`. Total runs from the earliest span to `now`, or is `nil` with no time at all.
    public static func interval(_ period: ReportPeriod, spans: [TimeSpan], now: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .week: return Stats.week(containing: now, calendar: calendar)
        case .month: return calendar.dateInterval(of: .month, for: now)
        case .year: return calendar.dateInterval(of: .year, for: now)
        case .total:
            guard let first = spans.map(\.start).min(), first < now else { return nil }
            return DateInterval(start: first, end: now)
        }
    }

    /// Largest area first, largest activity first inside it; ties by name. Archived activities count too.
    public static func build(spans: [TimeSpan], activities: [Activity], areas: [Area], in interval: DateInterval) -> [AreaTotal] {
        let byActivity = Stats.totalsByActivity(spans, in: interval)
        let areasByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        var groups: [UUID?: [ActivityTotal]] = [:]
        for activity in activities {
            guard let seconds = byActivity[activity.id], seconds > 0 else { continue }
            let areaID = activity.areaID.flatMap { areasByID[$0] }?.id
            groups[areaID, default: []].append(ActivityTotal(activity: activity, seconds: seconds))
        }
        return groups.map { areaID, totals in
            AreaTotal(
                area: areaID.flatMap { areasByID[$0] },
                seconds: totals.reduce(0) { $0 + $1.seconds },
                activities: totals.sorted { ($0.seconds, $1.activity.name) > ($1.seconds, $0.activity.name) }
            )
        }
        .sorted { ($0.seconds, $1.area?.name ?? "") > ($1.seconds, $0.area?.name ?? "") }
    }
}

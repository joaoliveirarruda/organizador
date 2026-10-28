import Foundation

/// One VEVENT as written in an .ics feed (before recurrence expansion).
public struct ICSEvent: Hashable, Sendable {
    public var uid: String
    public var summary: String
    public var location: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Time zone the event's wall-clock times are in. Recurrences are expanded in it.
    public var timeZone: TimeZone
    public var rule: RecurrenceRule?
    public var exceptionDates: Set<Date>
    /// Set on an edited occurrence of a recurring event: the original start it replaces.
    public var recurrenceID: Date?
    public var isCancelled: Bool

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public struct RecurrenceRule: Hashable, Sendable {
    public enum Frequency: String, Sendable {
        case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
    }

    /// A BYDAY entry such as "MO" or "2TU" (second Tuesday) or "-1FR" (last Friday).
    public struct WeekdayEntry: Hashable, Sendable {
        /// 0 = Monday ... 6 = Sunday.
        public var weekday: Int
        public var ordinal: Int?
    }

    public var frequency: Frequency
    public var interval: Int
    public var count: Int?
    public var until: Date?
    public var byDay: [WeekdayEntry]
    public var byMonthDay: [Int]
}

/// An occurrence ready to show: recurring events are already expanded.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var location: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
}

// MARK: - Parsing

public enum ICSParser {
    /// Parses the VEVENTs in an iCalendar feed. Floating and all-day times use `defaultTimeZone`.
    public static func parse(_ text: String, defaultTimeZone: TimeZone = .current) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var current: [Property]?
        var nestedDepth = 0

        for line in unfoldedLines(text) {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                current = []
                nestedDepth = 0
            } else if upper == "END:VEVENT" {
                if let properties = current, let event = makeEvent(properties, defaultTimeZone: defaultTimeZone) {
                    events.append(event)
                }
                current = nil
            } else if current != nil {
                if upper.hasPrefix("BEGIN:") {
                    nestedDepth += 1
                } else if upper.hasPrefix("END:") {
                    nestedDepth = max(0, nestedDepth - 1)
                } else if nestedDepth == 0, let property = Property(line: line) {
                    current?.append(property)
                }
            }
        }
        return events
    }

    struct Property {
        var name: String
        var params: [String: String]
        var value: String

        init?(line: String) {
            var inQuotes = false
            var colonIndex: String.Index?
            for index in line.indices {
                let char = line[index]
                if char == "\"" { inQuotes.toggle() }
                if char == ":" && !inQuotes {
                    colonIndex = index
                    break
                }
            }
            guard let colonIndex else { return nil }
            let head = line[..<colonIndex]
            value = String(line[line.index(after: colonIndex)...])

            var parts: [String] = []
            var part = ""
            inQuotes = false
            for char in head {
                if char == "\"" { inQuotes.toggle() }
                if char == ";" && !inQuotes {
                    parts.append(part)
                    part = ""
                } else {
                    part.append(char)
                }
            }
            parts.append(part)

            name = parts[0].uppercased()
            var params: [String: String] = [:]
            for param in parts.dropFirst() {
                guard let equals = param.firstIndex(of: "=") else { continue }
                let key = param[..<equals].uppercased()
                let raw = String(param[param.index(after: equals)...])
                params[key] = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            self.params = params
        }
    }

    /// Splits into lines and joins continuation lines (those starting with a space or tab).
    static func unfoldedLines(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for char in text {
            if escaping {
                switch char {
                case "n", "N": result.append("\n")
                default: result.append(char)
                }
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                result.append(char)
            }
        }
        return result
    }

    private static func makeEvent(_ properties: [Property], defaultTimeZone: TimeZone) -> ICSEvent? {
        func first(_ name: String) -> Property? { properties.first { $0.name == name } }

        guard let startProperty = first("DTSTART"),
              let start = parseDate(startProperty.value, params: startProperty.params, defaultTimeZone: defaultTimeZone)
        else { return nil }

        var end: Date
        if let endProperty = first("DTEND"),
           let parsed = parseDate(endProperty.value, params: endProperty.params, defaultTimeZone: defaultTimeZone) {
            end = parsed.date
        } else if let durationProperty = first("DURATION"), let seconds = parseDuration(durationProperty.value) {
            end = start.date.addingTimeInterval(seconds)
        } else {
            end = start.isAllDay ? start.date.addingTimeInterval(86_400) : start.date
        }
        if end < start.date { end = start.date }

        var exceptions = Set<Date>()
        for property in properties where property.name == "EXDATE" {
            for value in property.value.split(separator: ",") {
                if let parsed = parseDate(String(value), params: property.params, defaultTimeZone: defaultTimeZone) {
                    exceptions.insert(parsed.date)
                }
            }
        }

        let recurrenceID = first("RECURRENCE-ID").flatMap {
            parseDate($0.value, params: $0.params, defaultTimeZone: defaultTimeZone)?.date
        }

        return ICSEvent(
            uid: first("UID")?.value ?? UUID().uuidString,
            summary: first("SUMMARY").map { unescape($0.value) } ?? "(sem título)",
            location: first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
            start: start.date,
            end: end,
            isAllDay: start.isAllDay,
            timeZone: start.timeZone,
            rule: first("RRULE").flatMap { parseRule($0.value, timeZone: start.timeZone) },
            exceptionDates: exceptions,
            recurrenceID: recurrenceID,
            isCancelled: first("STATUS")?.value.uppercased() == "CANCELLED"
        )
    }

    /// Parses "20261028", "20261028T090000" (with optional TZID) or "20261028T120000Z".
    static func parseDate(
        _ value: String,
        params: [String: String],
        defaultTimeZone: TimeZone
    ) -> (date: Date, isAllDay: Bool, timeZone: TimeZone)? {
        let text = value.trimmingCharacters(in: .whitespaces)
        let digits = Array(text)
        func number(_ from: Int, _ length: Int) -> Int? {
            guard digits.count >= from + length else { return nil }
            return Int(String(digits[from..<(from + length)]))
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2) else { return nil }

        let isAllDay = params["VALUE"]?.uppercased() == "DATE" || digits.count == 8
        let timeZone: TimeZone
        if text.hasSuffix("Z") {
            timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid) {
            timeZone = zone
        } else {
            timeZone = defaultTimeZone
        }

        var components = DateComponents(year: year, month: month, day: day)
        if !isAllDay {
            guard digits.count >= 15, digits[8] == "T",
                  let hour = number(9, 2), let minute = number(11, 2), let second = number(13, 2)
            else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = second
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: components) else { return nil }
        // An all-day event belongs to the local calendar day, not to a UTC instant.
        return (date, isAllDay, isAllDay ? defaultTimeZone : timeZone)
    }

    /// Parses durations like "PT1H30M", "P1D" or "P1W".
    static func parseDuration(_ value: String) -> TimeInterval? {
        var text = value.uppercased()
        var sign: Double = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() }
        if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        text.removeFirst()

        var total: TimeInterval = 0
        var number = ""
        for char in text {
            if char.isNumber {
                number.append(char)
                continue
            }
            if char == "T" { continue }
            guard let amount = Double(number) else { return nil }
            switch char {
            case "W": total += amount * 604_800
            case "D": total += amount * 86_400
            case "H": total += amount * 3600
            case "M": total += amount * 60
            case "S": total += amount
            default: return nil
            }
            number = ""
        }
        return sign * total
    }

    static func parseRule(_ value: String, timeZone: TimeZone) -> RecurrenceRule? {
        var fields: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            if pieces.count == 2 { fields[pieces[0].uppercased()] = String(pieces[1]) }
        }
        guard let freqText = fields["FREQ"], let frequency = RecurrenceRule.Frequency(rawValue: freqText.uppercased())
        else { return nil }

        var until: Date?
        if let untilText = fields["UNTIL"],
           let parsed = parseDate(untilText, params: [:], defaultTimeZone: timeZone) {
            // A date-only UNTIL includes that whole day.
            until = parsed.isAllDay ? parsed.date.addingTimeInterval(86_399) : parsed.date
        }

        let weekdays = ["MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6]
        let byDay: [RecurrenceRule.WeekdayEntry] = (fields["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { entry in
                let text = entry.uppercased()
                guard text.count >= 2, let weekday = weekdays[String(text.suffix(2))] else { return nil }
                let prefix = text.dropLast(2)
                return RecurrenceRule.WeekdayEntry(weekday: weekday, ordinal: prefix.isEmpty ? nil : Int(prefix))
            }

        return RecurrenceRule(
            frequency: frequency,
            interval: max(1, Int(fields["INTERVAL"] ?? "") ?? 1),
            count: fields["COUNT"].flatMap { Int($0) },
            until: until,
            byDay: byDay,
            byMonthDay: (fields["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }
        )
    }
}

// MARK: - Expansion

public enum CalendarExpansion {
    /// Occurrences overlapping `window`, sorted by start. Handles RRULE, EXDATE,
    /// edited occurrences (RECURRENCE-ID) and cancelled events.
    public static func occurrences(of events: [ICSEvent], in window: DateInterval) -> [CalendarEvent] {
        var overrides: [String: Set<Date>] = [:]
        for event in events {
            if let recurrenceID = event.recurrenceID {
                overrides[event.uid, default: []].insert(recurrenceID)
            }
        }

        var result: [CalendarEvent] = []
        for event in events where !event.isCancelled || event.recurrenceID != nil {
            if event.recurrenceID != nil {
                // An edited occurrence stands on its own; a cancelled one just hides the original.
                if !event.isCancelled, overlaps(event.start, event.end, window) {
                    result.append(occurrence(event, start: event.start, end: event.end))
                }
                continue
            }
            guard let rule = event.rule else {
                if overlaps(event.start, event.end, window) {
                    result.append(occurrence(event, start: event.start, end: event.end))
                }
                continue
            }
            let replaced = overrides[event.uid] ?? []
            for start in RecurrenceExpander.starts(of: event, rule: rule, through: window.end)
            where !event.exceptionDates.contains(start) && !replaced.contains(start) {
                let end = start.addingTimeInterval(event.duration)
                if overlaps(start, end, window) {
                    result.append(occurrence(event, start: start, end: end))
                }
            }
        }
        return result.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    static func overlaps(_ start: Date, _ end: Date, _ window: DateInterval) -> Bool {
        if end > start { return start < window.end && end > window.start }
        return start >= window.start && start < window.end
    }

    private static func occurrence(_ event: ICSEvent, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(
            id: "\(event.uid)@\(start.timeIntervalSince1970)",
            title: event.summary,
            location: event.location,
            start: start,
            end: end,
            isAllDay: event.isAllDay
        )
    }
}

enum RecurrenceExpander {
    private static let maxPeriods = 5000

    /// Start dates of a recurring event in order, up to `limit`, honoring COUNT and UNTIL.
    static func starts(of event: ICSEvent, rule: RecurrenceRule, through limit: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZone
        let start = event.start
        var results: [Date] = []
        var produced = 0

        /// Returns false once no more occurrences should be generated.
        func accept(_ date: Date) -> Bool {
            if let until = rule.until, date > until { return false }
            if let count = rule.count, produced >= count { return false }
            if date > limit { return false }
            results.append(date)
            produced += 1
            return true
        }

        func pastEnd(_ periodStart: Date) -> Bool {
            if periodStart > limit { return true }
            if let until = rule.until, periodStart > until { return true }
            if let count = rule.count, produced >= count { return true }
            return false
        }

        switch rule.frequency {
        case .daily:
            let allowed = Set(rule.byDay.map(\.weekday))
            for period in 0..<maxPeriods {
                guard let date = calendar.date(byAdding: .day, value: period * rule.interval, to: start) else { break }
                if pastEnd(date) { break }
                if !allowed.isEmpty, !allowed.contains(weekdayIndex(date, calendar)) { continue }
                if !accept(date) { break }
            }

        case .weekly:
            let weekdays = rule.byDay.isEmpty
                ? [weekdayIndex(start, calendar)]
                : Array(Set(rule.byDay.map(\.weekday))).sorted()
            guard let weekStart = calendar.date(byAdding: .day, value: -weekdayIndex(start, calendar), to: start)
            else { break }
            periods: for period in 0..<maxPeriods {
                guard let base = calendar.date(byAdding: .day, value: period * rule.interval * 7, to: weekStart)
                else { break }
                if pastEnd(base) { break }
                for weekday in weekdays {
                    guard let date = calendar.date(byAdding: .day, value: weekday, to: base) else { continue }
                    if date < start { continue }
                    if !accept(date) { break periods }
                }
            }

        case .monthly:
            let time = calendar.dateComponents([.hour, .minute, .second], from: start)
            let startMonth = calendar.dateComponents([.year, .month], from: start)
            periods: for period in 0..<maxPeriods {
                guard let firstOfMonth = calendar.date(from: DateComponents(
                    year: startMonth.year, month: (startMonth.month ?? 1) + period * rule.interval, day: 1,
                    hour: time.hour, minute: time.minute, second: time.second
                )) else { break }
                if pastEnd(firstOfMonth) { break }
                let candidates = monthlyCandidates(
                    in: firstOfMonth, rule: rule, startDay: calendar.component(.day, from: start), calendar: calendar
                )
                for date in candidates where date >= start {
                    if !accept(date) { break periods }
                }
            }

        case .yearly:
            let startDay = calendar.component(.day, from: start)
            for period in 0..<maxPeriods {
                guard let date = calendar.date(byAdding: .year, value: period * rule.interval, to: start) else { break }
                if pastEnd(date) { break }
                // Feb 29 only happens on leap years.
                if calendar.component(.day, from: date) != startDay { continue }
                if !accept(date) { break }
            }
        }
        return results
    }

    /// Occurrence dates within the month that starts at `firstOfMonth`, sorted.
    private static func monthlyCandidates(
        in firstOfMonth: Date,
        rule: RecurrenceRule,
        startDay: Int,
        calendar: Calendar
    ) -> [Date] {
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }
        func day(_ number: Int) -> Date? {
            guard number >= 1, number <= daysInMonth else { return nil }
            return calendar.date(byAdding: .day, value: number - 1, to: firstOfMonth)
        }

        var days: [Int] = []
        if !rule.byDay.isEmpty {
            let firstWeekday = weekdayIndex(firstOfMonth, calendar)
            for entry in rule.byDay {
                let firstMatch = 1 + (entry.weekday - firstWeekday + 7) % 7
                let matches = Array(stride(from: firstMatch, through: daysInMonth, by: 7))
                if let ordinal = entry.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                    if matches.indices.contains(index) { days.append(matches[index]) }
                } else {
                    days.append(contentsOf: matches)
                }
            }
        } else if !rule.byMonthDay.isEmpty {
            for value in rule.byMonthDay {
                days.append(value > 0 ? value : daysInMonth + value + 1)
            }
        } else {
            // Same day as the first occurrence; months without that day are skipped.
            days.append(startDay)
        }
        return Array(Set(days)).sorted().compactMap(day)
    }

    /// 0 = Monday ... 6 = Sunday.
    static func weekdayIndex(_ date: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}

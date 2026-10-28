import Foundation

public enum DurationFormat {
    /// "1:02:03"
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    /// "3h 15min", "3h", "15min", "<1min" for a few seconds
    public static func short(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "<1min" }
        let totalMinutes = max(0, Int((seconds / 60).rounded(.down)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)min"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)min"
        }
    }
}

extension DurationFormat {
    /// "18h40", "6h", "30min" — the report's compact hours.
    public static func compact(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded(.down)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)min"
        case (_, 0): return "\(hours)h"
        default: return String(format: "%dh%02d", hours, minutes)
        }
    }
}

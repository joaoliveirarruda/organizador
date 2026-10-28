import Foundation

/// What a timed session looks like as an event in the macOS Calendar.
public struct SessionEvent: Hashable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date

    /// "⏱ Area · Goal", or "⏱ Area" for an area without a goal.
    public static func make(_ session: FocusSession, area: Activity?, goal: Goal?) -> SessionEvent {
        let name = area?.name ?? "Área removida"
        let title = goal.map { "⏱ \(name) · \($0.title)" } ?? "⏱ \(name)"
        return SessionEvent(title: title, start: session.start, end: session.end)
    }
}

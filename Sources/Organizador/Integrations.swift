import AppKit
import EventKit
import Observation
import OrganizadorCore
import UserNotifications

/// Writes sessions as events in the macOS Calendar (and so in Google or iCloud calendars added to the Mac).
@MainActor
@Observable
final class CalendarExporter {
    enum Access { case unknown, granted, denied, unavailable }

    private(set) var access: Access = .unknown
    /// Calendars that accept new events.
    private(set) var calendars: [EKCalendar] = []
    @ObservationIgnored var onError: (String) -> Void = { _ in }
    @ObservationIgnored private let store = EKEventStore()

    /// Asking for access without the usage text in Info.plist kills the app, so `swift run` builds can't export.
    private static var canAsk: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    func connect() {
        guard Self.canAsk else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        case .notDetermined:
            Task {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                access = granted ? .granted : .denied
                if granted { calendars = store.calendars(for: .event).filter(\.allowsContentModifications) }
            }
        default:
            access = .denied
        }
    }

    /// Creates the session's event, or updates the one already there. Returns the event identifier.
    func upsert(_ event: SessionEvent, sessionID: UUID, eventID: String?, calendarID: String) -> String? {
        guard access == .granted else { return nil }
        // The marker URL finds the event even when the app quit before saving its identifier.
        let ekEvent = eventID.flatMap(store.event(withIdentifier:))
            ?? find(sessionID, around: event.start, event.end)
            ?? EKEvent(eventStore: store)
        if ekEvent.calendar == nil {
            ekEvent.calendar = store.calendar(withIdentifier: calendarID) ?? store.defaultCalendarForNewEvents
        }
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.url = Self.marker(sessionID)
        do {
            try store.save(ekEvent, span: .thisEvent, commit: true)
            return ekEvent.eventIdentifier
        } catch {
            onError("Não foi possível salvar a sessão no Calendário: \(error.localizedDescription)")
            return nil
        }
    }

    func remove(sessionID: UUID, eventID: String?) {
        guard access == .granted, let event = eventID.flatMap(store.event(withIdentifier:)) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    private func find(_ sessionID: UUID, around start: Date, _ end: Date) -> EKEvent? {
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-86_400), end: end.addingTimeInterval(86_400), calendars: nil
        )
        let marker = Self.marker(sessionID)
        return store.events(matching: predicate).first { $0.url == marker }
    }

    private static func marker(_ sessionID: UUID) -> URL {
        URL(string: "organizador://session/\(sessionID.uuidString)")!
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

/// The once-a-day macOS notification about stalled goals.
enum StaleNotifier {
    /// Posted when the user clicks the notification.
    static let openHome = Notification.Name("OrganizadorOpenHome")

    /// UNUserNotificationCenter crashes outside an app bundle (`swift run`).
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postOncePerDay(_ text: String, today: Date) {
        guard isAvailable else { return }
        let key = "lastStaleNoticeDay"
        guard UserDefaults.standard.object(forKey: key) as? Date != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = "Frentes paradas"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stale-goals", content: content, trigger: nil))
    }

    static func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }
}

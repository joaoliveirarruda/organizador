import AppKit
import Foundation
import Observation
import OrganizadorCore

/// App state shared by the window and the menu bar. Every change is saved to disk right away.
@MainActor
@Observable
final class AppModel {
    private(set) var data: AppData
    /// Updated every second so running timers and totals refresh.
    private(set) var now = Date()
    var lastError: String?
    /// Shown when the timer was paused automatically (idle or sleep).
    var pauseNotice: String?

    let calendar = Calendar.current
    private let store: JSONStore?
    /// False when the data file could not be read, so we never overwrite it with empty data.
    private let canSave: Bool
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: JSONStore? = AppModel.makeDefaultStore()) {
        var loaded = AppData.empty
        var loadError: String?
        if let store {
            do {
                loaded = try store.load()
            } catch {
                loadError = "Não foi possível ler os dados em \(store.url.path): \(error.localizedDescription)"
            }
        }
        if loadError == nil, loaded.activities.isEmpty, loaded.sessions.isEmpty {
            loaded.activities = Self.starterActivities()
        }

        self.store = store
        self.canSave = loadError == nil
        self.data = loaded
        self.lastError = loadError

        startTicker()
        observeSystemEvents()
    }

    nonisolated static func makeDefaultStore() -> JSONStore? {
        guard let url = try? JSONStore.defaultURL() else { return nil }
        return JSONStore(url: url)
    }

    private static func starterActivities() -> [Activity] {
        [
            Activity(name: "Estudo", colorHex: Palette.colors[3]),
            Activity(name: "Trabalho", colorHex: Palette.colors[4]),
            Activity(name: "Leitura", colorHex: Palette.colors[2]),
            Activity(name: "Exercício", colorHex: Palette.colors[0]),
        ]
    }

    var dataFileURL: URL? { store?.url }

    // MARK: - Reading

    var running: RunningTimer? { data.running }

    var activeActivities: [Activity] { data.activities.filter { !$0.isArchived } }

    func activity(_ id: UUID) -> Activity? {
        data.activities.first { $0.id == id }
    }

    var runningActivity: Activity? {
        running.flatMap { activity($0.activityID) }
    }

    var spans: [TimeSpan] {
        Stats.spans(sessions: data.sessions, running: data.running, now: now)
    }

    var today: DateInterval { Stats.day(containing: now, calendar: calendar) }

    var todayTotal: TimeInterval { Stats.total(spans, in: today) }

    func todayTotal(for activityID: UUID) -> TimeInterval {
        Stats.total(spans, in: today, activityIDs: [activityID])
    }

    var currentElapsed: TimeInterval {
        TimerEngine(running: data.running).elapsed(at: now)
    }

    var dailyTarget: TimeInterval { TimeInterval(data.preferences.dailyTargetMinutes * 60) }

    var todayTimeline: [Stats.TimelineSegment] { Stats.timeline(spans, day: today) }

    func dailyTotals(days: Int) -> [Stats.DailyActivityTotal] {
        Stats.dailyTotalsByActivity(spans, days: days, endingOn: now, calendar: calendar)
    }

    /// Time per activity over the last `days` days, largest first.
    func totalsByActivity(lastDays days: Int) -> [(activity: Activity, seconds: TimeInterval)] {
        let interval = Stats.lastDays(days, endingOn: now, calendar: calendar)
        return Stats.totalsByActivity(spans, in: interval)
            .compactMap { id, seconds in activity(id).map { (activity: $0, seconds: seconds) } }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Finished sessions grouped by the day they started, newest first.
    var sessionsByDay: [(day: Date, sessions: [FocusSession])] {
        let grouped = Dictionary(grouping: data.sessions) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, sessions: grouped[day, default: []].sorted { $0.start > $1.start })
        }
    }

    var menuBarTitle: String {
        if let activity = runningActivity {
            return "\(activity.name) \(DurationFormat.clock(currentElapsed))"
        }
        return DurationFormat.clock(todayTotal)
    }

    // MARK: - Timer

    /// Starts the activity, or pauses it if it is the one running.
    func toggle(_ activityID: UUID) {
        let date = Date()
        now = date
        var engine = TimerEngine(running: data.running)
        let finished = data.running?.activityID == activityID
            ? engine.stop(at: date)
            : engine.start(activityID, at: date)
        if let finished { data.sessions.append(finished) }
        data.running = engine.running
        pauseNotice = nil
        persist()
    }

    func stop(at date: Date = Date()) {
        var engine = TimerEngine(running: data.running)
        guard engine.isRunning else { return }
        if let finished = engine.stop(at: date) { data.sessions.append(finished) }
        data.running = engine.running
        now = Date()
        persist()
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        now = Date()
        pauseIfIdle()
    }

    private func pauseIfIdle() {
        guard let running = data.running, data.preferences.idlePauseMinutes > 0 else { return }
        let idle = IdleMonitor.secondsSinceLastInput()
        guard idle >= TimeInterval(data.preferences.idlePauseMinutes * 60) else { return }
        let lastInput = max(running.startedAt, now.addingTimeInterval(-idle))
        stop(at: lastInput)
        let name = activity(running.activityID)?.name ?? "A atividade"
        pauseNotice = "\(name) foi pausada por inatividade às \(lastInput.formatted(date: .omitted, time: .shortened))."
    }

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let running = self.runningActivity else { return }
                self.stop()
                self.pauseNotice = "\(running.name) foi pausada porque o Mac entrou em repouso."
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
    }

    // MARK: - Activities

    func addActivity(name: String, colorHex: String) {
        data.activities.append(Activity(name: name, colorHex: colorHex))
        persist()
    }

    func updateActivity(_ activity: Activity) {
        guard let index = data.activities.firstIndex(where: { $0.id == activity.id }) else { return }
        data.activities[index] = activity
        persist()
    }

    func archiveActivity(_ id: UUID) {
        if data.running?.activityID == id { stop() }
        guard let index = data.activities.firstIndex(where: { $0.id == id }) else { return }
        data.activities[index].isArchived = true
        persist()
    }

    // MARK: - Sessions

    /// Adds the session, or replaces the one with the same id.
    func saveSession(_ session: FocusSession) {
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            data.sessions[index] = session
        } else {
            data.sessions.append(session)
        }
        persist()
    }

    func deleteSession(_ id: UUID) {
        data.sessions.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Preferences

    func setDailyTarget(minutes: Int) {
        data.preferences.dailyTargetMinutes = max(0, minutes)
        persist()
    }

    func setIdlePause(minutes: Int) {
        data.preferences.idlePauseMinutes = max(0, minutes)
        persist()
    }

    private func persist() {
        guard let store, canSave else { return }
        do {
            try store.save(data)
        } catch {
            lastError = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }
}

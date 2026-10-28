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
    /// The page shown in the main window.
    var route: Route = .home

    let calendar = Calendar.current
    /// Meetings from the user's calendar link.
    let agenda: CalendarFeed
    /// The notes folder.
    let notes: NotesLibrary
    /// Writes finished sessions to the macOS Calendar.
    let calendarExport = CalendarExporter()
    private let store: JSONStore?
    /// False when the data file could not be read, so we never overwrite it with empty data.
    private let canSave: Bool
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastStaleCheck = Date.distantPast

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
        if loadError == nil, loaded.financeCategories.isEmpty {
            loaded.financeCategories = Finance.defaultCategories()
        }

        self.store = store
        self.agenda = CalendarFeed(
            cacheURL: store?.url.deletingLastPathComponent().appendingPathComponent("calendar.ics")
        )
        let notesPath = loaded.preferences.notesFolderPath
        self.notes = NotesLibrary(folder: notesPath.isEmpty
            ? Self.defaultNotesFolder(next: store)
            : URL(fileURLWithPath: notesPath, isDirectory: true))
        self.canSave = loadError == nil
        self.data = loaded
        self.lastError = loadError

        notes.onError = { [weak self] in self?.lastError = $0 }
        calendarExport.onError = { [weak self] in self?.lastError = $0 }
        if loaded.preferences.exportSessionsToCalendar { calendarExport.connect() }
        if loaded.preferences.staleGoalNotifications { StaleNotifier.requestPermission() }
        startTicker()
        observeSystemEvents()
    }

    private static func defaultNotesFolder(next store: JSONStore?) -> URL {
        (store?.url.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Notas", isDirectory: true)
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

    /// Where icons and covers of goals and areas are copied to.
    var imagesFolder: URL {
        (store?.url.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Imagens", isDirectory: true)
    }

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
        data.running = engine.running
        if let finished { appendSession(finished) }
        pauseNotice = nil
        persist()
    }

    /// Starts the activity; does nothing if it is already running.
    func start(_ activityID: UUID) {
        guard data.running?.activityID != activityID else { return }
        toggle(activityID)
    }

    func stop(at date: Date = Date()) {
        var engine = TimerEngine(running: data.running)
        guard engine.isRunning else { return }
        let finished = engine.stop(at: date)
        data.running = engine.running
        now = Date()
        if let finished { appendSession(finished) }
        persist()
    }

    /// Records a finished session, saving it before it goes to the calendar.
    private func appendSession(_ session: FocusSession) {
        data.sessions.append(session)
        persist()
        exportToCalendar(session.id, isNew: true)
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
        agenda.refreshIfDue(urlString: data.preferences.calendarURL)
        if now.timeIntervalSince(lastStaleCheck) >= 600 {
            lastStaleCheck = now
            notifyStalledGoals()
        }
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

    @discardableResult
    func addActivity(name: String, colorHex: String, goalID: UUID? = nil, areaID: UUID? = nil, icon: Icon? = nil, cover: String? = nil) -> Activity {
        let activity = Activity(name: name, colorHex: colorHex, goalID: goalID, areaID: areaID, icon: icon, cover: cover)
        data.activities.append(activity)
        persist()
        return activity
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

    // MARK: - Areas

    var areas: [Area] {
        data.areas.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func area(_ id: UUID?) -> Area? {
        guard let id else { return nil }
        return data.areas.first { $0.id == id }
    }

    @discardableResult
    func addArea(name: String, colorHex: String) -> Area {
        let area = Area(name: name, colorHex: colorHex)
        data.areas.append(area)
        persist()
        return area
    }

    func updateArea(_ area: Area) {
        guard let index = data.areas.firstIndex(where: { $0.id == area.id }) else { return }
        data.areas[index] = area
        persist()
    }

    /// Its activities lose the area; their sessions stay as they are.
    func deleteArea(_ id: UUID) {
        data.areas.removeAll { $0.id == id }
        for index in data.activities.indices where data.activities[index].areaID == id {
            data.activities[index].areaID = nil
        }
        persist()
    }

    func report(_ period: ReportPeriod) -> (interval: DateInterval?, areas: [TimeReport.AreaTotal]) {
        guard let interval = TimeReport.interval(period, spans: spans, now: now, calendar: calendar) else { return (nil, []) }
        return (interval, TimeReport.build(spans: spans, activities: data.activities, areas: data.areas, in: interval))
    }

    // MARK: - Goals

    func goal(_ id: UUID) -> Goal? {
        data.goals.first { $0.id == id }
    }

    /// Goals with the nearest deadline first; goals without a deadline last.
    var sortedGoals: [Goal] {
        data.goals.sorted { lhs, rhs in
            switch (lhs.deadline, rhs.deadline) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }
    }

    var activeGoals: [Goal] { sortedGoals.filter { $0.status == .active } }

    /// Paused and closed goals, kept out of the main lists.
    var inactiveGoals: [Goal] { sortedGoals.filter { $0.status != .active } }

    func updateGoal(_ goal: Goal) {
        guard let index = data.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        data.goals[index] = goal
        persist()
    }

    func setGoalStatus(_ id: UUID, _ status: GoalStatus) {
        guard let index = data.goals.firstIndex(where: { $0.id == id }) else { return }
        data.goals[index].status = status
        persist()
    }

    /// "Fio da meada": every goal's state, in `data.goals` order.
    var threads: [GoalThread] {
        GoalThreads.compute(data: data, notes: notes.notes, now: now, calendar: calendar)
    }

    func thread(for goalID: UUID) -> GoalThread? {
        threads.first { $0.goal.id == goalID }
    }

    /// This week's time on areas without a goal.
    var looseAreasWeekTotal: TimeInterval {
        let loose = Set(data.activities.filter { $0.goalID.map(goal) == nil }.map(\.id))
        return Stats.total(spans, in: Stats.week(containing: now, calendar: calendar), activityIDs: loose)
    }

    func weekTotal(for activityID: UUID) -> TimeInterval {
        Stats.total(spans, in: Stats.week(containing: now, calendar: calendar), activityIDs: [activityID])
    }

    /// Sends the daily notification about stalled goals, at most once a day.
    private func notifyStalledGoals() {
        guard data.preferences.staleGoalNotifications, let text = GoalThreads.notice(threads) else { return }
        StaleNotifier.postOncePerDay(text, today: calendar.startOfDay(for: now))
    }

    /// Activities whose time counts toward the goal, archived ones included.
    func activities(forGoal goalID: UUID) -> [Activity] {
        data.activities.filter { $0.goalID == goalID }
    }

    func progress(for goal: Goal) -> GoalProgress {
        GoalProgress.compute(for: goal, activities: data.activities, spans: spans, now: now)
    }

    /// Time logged this calendar week on the goal's activities.
    func thisWeekTotal(for goal: Goal) -> TimeInterval {
        let ids = Set(activities(forGoal: goal.id).map(\.id))
        return Stats.total(spans, in: Stats.week(containing: now, calendar: calendar), activityIDs: ids)
    }

    /// Adds or replaces the goal and makes exactly `activityIDs` count toward it.
    /// An activity can feed one goal only, so selecting it here moves it from any other goal.
    func saveGoal(_ goal: Goal, activityIDs: Set<UUID>) {
        if let index = data.goals.firstIndex(where: { $0.id == goal.id }) {
            data.goals[index] = goal
        } else {
            data.goals.append(goal)
        }
        for index in data.activities.indices {
            if activityIDs.contains(data.activities[index].id) {
                data.activities[index].goalID = goal.id
            } else if data.activities[index].goalID == goal.id {
                data.activities[index].goalID = nil
            }
        }
        persist()
    }

    /// Deletes the goal. Its activities and their sessions are kept.
    func deleteGoal(_ id: UUID) {
        data.goals.removeAll { $0.id == id }
        for index in data.activities.indices where data.activities[index].goalID == id {
            data.activities[index].goalID = nil
        }
        for index in data.tasks.indices where data.tasks[index].goalID == id {
            data.tasks[index].goalID = nil
        }
        persist()
    }

    /// Completed and total tasks linked to the goal.
    func taskCounts(forGoal goalID: UUID) -> (done: Int, total: Int) {
        let linked = data.tasks.filter { $0.goalID == goalID }
        return (linked.filter(\.isDone).count, linked.count)
    }

    // MARK: - Links

    /// Opens a `[[link]]`: a note, an objective or a task. A link to nothing creates the note, as in Obsidian.
    func open(link target: String) {
        if let node = NoteGraph.resolve(target, notes: notes.notes, goals: data.goals, tasks: data.tasks) {
            open(node.ref)
        } else if let note = notes.create(title: target) {
            route = .note(note.url)
        }
    }

    func open(_ ref: GraphNode.Ref) {
        switch ref {
        case .note(let url): route = .note(url)
        case .goal(let id): route = .goal(id)
        case .task: route = .tasks
        }
    }

    // MARK: - Tasks

    var todayTasks: [TaskItem] { TaskLists.today(data.tasks, now: now, calendar: calendar) }

    var upcomingTasks: [TaskItem] { TaskLists.upcoming(data.tasks, now: now, calendar: calendar) }

    var completedTasks: [TaskItem] { TaskLists.completed(data.tasks) }

    func isOverdue(_ task: TaskItem) -> Bool {
        TaskLists.isOverdue(task, now: now, calendar: calendar)
    }

    func addTask(title: String, due: Date?) {
        data.tasks.append(TaskItem(title: title, dueDate: due.map(calendar.startOfDay)))
        persist()
    }

    /// Adds the task, or replaces the one with the same id.
    func saveTask(_ task: TaskItem) {
        if let index = data.tasks.firstIndex(where: { $0.id == task.id }) {
            data.tasks[index] = task
        } else {
            data.tasks.append(task)
        }
        persist()
    }

    func toggleTaskDone(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].completedAt = data.tasks[index].isDone ? nil : Date()
        persist()
    }

    func deleteTask(_ id: UUID) {
        data.tasks.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Habits

    var habitTracker: HabitTracker {
        HabitTracker(checks: data.habitChecks, spans: spans, calendar: calendar)
    }

    func habit(_ id: UUID) -> Habit? {
        data.habits.first { $0.id == id }
    }

    /// Checks or unchecks the habit on `day`. Days done by the timer stay done.
    func toggleHabit(_ habitID: UUID, on day: Date) {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: Date()) else { return }
        if let index = data.habitChecks.firstIndex(where: {
            $0.habitID == habitID && calendar.isDate($0.day, inSameDayAs: start)
        }) {
            data.habitChecks.remove(at: index)
        } else {
            data.habitChecks.append(HabitCheck(habitID: habitID, day: start))
        }
        persist()
    }

    /// Adds the habit, or replaces the one with the same id.
    func saveHabit(_ habit: Habit) {
        if let index = data.habits.firstIndex(where: { $0.id == habit.id }) {
            data.habits[index] = habit
        } else {
            data.habits.append(habit)
        }
        persist()
    }

    /// Deletes the habit and its checks.
    func deleteHabit(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        data.habitChecks.removeAll { $0.habitID == id }
        persist()
    }

    // MARK: - Sessions

    /// Adds the session, or replaces the one with the same id.
    func saveSession(_ session: FocusSession) {
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            var session = session
            session.calendarEventID = data.sessions[index].calendarEventID
            data.sessions[index] = session
            persist()
            exportToCalendar(session.id, isNew: false)
        } else {
            appendSession(session)
        }
    }

    func deleteSession(_ id: UUID) {
        let removed = data.sessions.first { $0.id == id }
        data.sessions.removeAll { $0.id == id }
        persist()
        if data.preferences.exportSessionsToCalendar, let removed {
            calendarExport.remove(removed)
        }
    }

    /// Creates or updates the session's calendar event. Sessions from before the export was
    /// turned on (no event yet) are left alone when edited.
    private func exportToCalendar(_ sessionID: UUID, isNew: Bool) {
        guard data.preferences.exportSessionsToCalendar,
              let index = data.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = data.sessions[index]
        guard isNew || session.calendarEventID != nil else { return }
        let area = activity(session.activityID)
        let event = SessionEvent.make(session, area: area, goal: area?.goalID.flatMap(goal))
        guard let eventID = calendarExport.upsert(
            event, sessionID: session.id, eventID: session.calendarEventID, calendarID: data.preferences.exportCalendarID
        ), eventID != session.calendarEventID else { return }
        data.sessions[index].calendarEventID = eventID
        persist()
    }

    // MARK: - Calendar

    func calendarEvents(on day: Date) -> [CalendarEvent] {
        agenda.occurrences(in: Stats.day(containing: day, calendar: calendar))
    }

    var hasCalendar: Bool { !data.preferences.calendarURL.isEmpty }

    func setCalendarURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        data.preferences.calendarURL = trimmed
        persist()
        if trimmed.isEmpty {
            agenda.clear()
        } else {
            agenda.refresh(urlString: trimmed)
        }
    }

    func refreshCalendar() {
        guard hasCalendar else { return }
        agenda.refresh(urlString: data.preferences.calendarURL)
    }

    // MARK: - Finance

    func financeCategory(_ id: UUID?) -> FinanceCategory? {
        guard let id else { return nil }
        return data.financeCategories.first { $0.id == id }
    }

    func month(containing date: Date) -> DateInterval {
        Finance.month(containing: date, calendar: calendar)
    }

    func transactions(in month: DateInterval) -> [MoneyTransaction] {
        Finance.transactions(data.transactions, in: month)
    }

    func monthSummary(_ month: DateInterval) -> MonthSummary {
        Finance.summary(data.transactions, in: month)
    }

    /// Adds the transaction, or replaces the one with the same id.
    func saveTransaction(_ transaction: MoneyTransaction) {
        if let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) {
            data.transactions[index] = transaction
        } else {
            data.transactions.append(transaction)
        }
        persist()
    }

    func setCategory(_ categoryID: UUID?, forTransaction id: UUID) {
        guard let index = data.transactions.firstIndex(where: { $0.id == id }) else { return }
        data.transactions[index].categoryID = categoryID
        persist()
    }

    func deleteTransaction(_ id: UUID) {
        data.transactions.removeAll { $0.id == id }
        persist()
    }

    /// Replaces all categories. Transactions in removed categories become uncategorized.
    func saveFinanceCategories(_ categories: [FinanceCategory]) {
        let kept = Set(categories.map(\.id))
        for index in data.transactions.indices {
            if let id = data.transactions[index].categoryID, !kept.contains(id) {
                data.transactions[index].categoryID = nil
            }
        }
        data.financeCategories = categories
        persist()
    }

    /// Adds the statement lines not imported before. Returns how many were added and skipped.
    @discardableResult
    func importStatement(_ lines: [StatementLine]) -> (added: Int, duplicates: Int) {
        let result = StatementImporter.newTransactions(from: lines, existing: data.transactions)
        data.transactions.append(contentsOf: result.transactions)
        persist()
        return (result.transactions.count, result.duplicates)
    }

    // MARK: - Preferences

    func setExportSessions(_ on: Bool) {
        data.preferences.exportSessionsToCalendar = on
        persist()
        if on { calendarExport.connect() }
    }

    func setExportCalendar(_ id: String) {
        data.preferences.exportCalendarID = id
        persist()
    }

    func setStaleGoalNotifications(_ on: Bool) {
        data.preferences.staleGoalNotifications = on
        persist()
        if on { StaleNotifier.requestPermission() }
    }

    func setDailyTarget(minutes: Int) {
        data.preferences.dailyTargetMinutes = max(0, minutes)
        persist()
    }

    func setIdlePause(minutes: Int) {
        data.preferences.idlePauseMinutes = max(0, minutes)
        persist()
    }

    /// Points the notes at another folder, or back at the default one when `url` is nil.
    func setNotesFolder(_ url: URL?) {
        data.preferences.notesFolderPath = url?.path ?? ""
        persist()
        notes.setFolder(url ?? Self.defaultNotesFolder(next: store))
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

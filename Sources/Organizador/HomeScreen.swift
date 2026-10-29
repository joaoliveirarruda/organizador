import AppKit
import OrganizadorCore
import SwiftUI

/// Hoje: one day at a time — meetings and timed work in one timeline, the day's tasks and habits.
/// Today also gets the box to start working and how every objective is doing.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var day = Date()
    @State private var newTask = ""
    @State private var creatingTask = false
    @State private var editingTask: TaskItem?
    @State private var deletingTask: TaskItem?
    @State private var addingSession = false
    @State private var editingSession: FocusSession?
    @State private var addingHabit = false

    var body: some View {
        let now = model.now
        let isToday = model.calendar.isDate(day, inSameDayAs: now)
        let threads = model.threads
        let active = threads.filter { $0.state == .active || $0.state == .stalled }
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(section: "Hoje", title: isToday ? greeting(now) : date, subtitle: isToday ? date : nil) {
                    PeriodStepper(currentTitle: "Hoje", isCurrent: isToday, step: shiftDay) { day = model.now }
                }

                if isToday {
                    StartBox()
                    if let notice = model.pauseNotice {
                        HStack {
                            Image(systemName: "pause.circle")
                            Text(notice)
                            Spacer()
                            Button("OK") { model.pauseNotice = nil }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
                    }
                }

                PageSection(title: "Agenda") {
                    timeline
                } accessory: {
                    if model.hasCalendar {
                        CalendarSyncStatus()
                        Button { model.refreshCalendar() } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel("Atualizar agenda")
                        .help("Atualizar agenda")
                    }
                    Button("Sessão", systemImage: "plus") { addingSession = true }
                        .buttonStyle(.heading())
                        .disabled(model.activeActivities.isEmpty)
                        .help("Registrar uma sessão que o cronômetro não pegou")
                }

                PageSection(title: "Tarefas") {
                    tasks(isToday: isToday)
                } accessory: {
                    Button("Todas   ›") { model.route = .tasks }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                }

                PageSection(title: "Hábitos") {
                    habits
                } accessory: {
                    if !model.data.habits.isEmpty {
                        Button("Constância   ›") { model.route = .habits }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                    }
                    Button("Hábito", systemImage: "plus") { addingHabit = true }.buttonStyle(.heading())
                }

                if isToday && !active.isEmpty {
                    PageSection(title: "Retomar de onde parei") {
                        ForEach(active, id: \.goal.id) { thread in
                            ThreadRow(thread: thread)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
        .floatingSheet(isPresented: $creatingTask) { TaskEditor(task: nil) }
        .floatingSheet(item: $editingTask) { TaskEditor(task: $0) }
        .floatingSheet(isPresented: $addingSession) { SessionEditor(session: nil) }
        .floatingSheet(item: $editingSession) { SessionEditor(session: $0) }
        .floatingSheet(isPresented: $addingHabit) { HabitEditor(habit: nil) }
        .appConfirm("Excluir tarefa?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible, presenting: deletingTask) { task in
            Button("Excluir tarefa", role: .destructive) { model.deleteTask(task.id); deletingTask = nil }
        } message: { _ in Text("A tarefa será removida.") }
    }

    /// Meetings and timed sessions of the day, in the order they happen.
    @ViewBuilder
    private var timeline: some View {
        let events = model.calendarEvents(on: day).map { DayItem.event($0) }
        let sessions = model.data.sessions
            .filter { model.calendar.isDate($0.start, inSameDayAs: day) }
            .map { DayItem.session($0) }
        let items = (events + sessions).sorted { $0.start < $1.start }
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text(model.hasCalendar ? "Nenhum compromisso ou sessão neste dia." : "Nenhuma sessão neste dia.")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            ForEach(items) { item in
                switch item {
                case .event(let event):
                    EventRow(event: event, now: model.now)
                case .session(let session):
                    DaySessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture { editingSession = session }
                }
            }
            if !model.hasCalendar {
                HStack(spacing: 6) {
                    Text("Conecte uma agenda para ver seus compromissos aqui.").foregroundStyle(Theme.secondaryText)
                    Button("Conectar   ›") { model.route = .settingsSection("Receber compromissos") }.buttonStyle(.plain)
                }
                .font(Theme.font(size: 12))
            }
        }
    }

    @ViewBuilder
    private func tasks(isToday: Bool) -> some View {
        // Today includes what is overdue; another day shows only what is due on it.
        let tasks = isToday ? model.todayTasks : model.data.tasks.filter { task in
            !task.isDone && task.dueDate.map { model.calendar.isDate($0, inSameDayAs: day) } == true
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(Theme.secondaryText).frame(width: 22)
                TextField("Nova tarefa para este dia (Enter para adicionar)", text: $newTask)
                    .textFieldStyle(.plain)
                    .onSubmit(addTask)
                Button("Detalhes…") { creatingTask = true }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
            }
            ForEach(tasks) { task in
                TaskRow(task: task)
                    .contentShape(Rectangle())
                    .onTapGesture { editingTask = task }
                    .appContextMenu {
                        Button("Editar") { editingTask = task }
                        Button("Excluir", role: .destructive) { deletingTask = task }
                    }
            }
        }
    }

    @ViewBuilder
    private var habits: some View {
        let tracker = model.habitTracker
        if model.data.habits.isEmpty {
            Text("Crie um hábito e marque aqui os dias em que fez. Ligado a uma atividade, o cronômetro marca sozinho.")
                .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.data.habits) { habit in
                    HabitTodayRow(habit: habit, tracker: tracker, now: day)
                }
            }
        }
    }

    private func shiftDay(_ amount: Int) {
        day = model.calendar.date(byAdding: .day, value: amount, to: day) ?? day
    }

    private func greeting(_ now: Date) -> String {
        let hour = model.calendar.component(.hour, from: now)
        let part = hour < 12 ? "Bom dia" : hour < 18 ? "Boa tarde" : "Boa noite"
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        model.addTask(title: title, due: day)
        newTask = ""
    }
}

/// A meeting or a timed session, so the day can list both in order.
private enum DayItem: Identifiable {
    case event(CalendarEvent)
    case session(FocusSession)

    var id: String {
        switch self {
        case .event(let event): "event-\(event.id)"
        case .session(let session): "session-\(session.id)"
        }
    }

    var start: Date {
        switch self {
        case .event(let event): event.start
        case .session(let session): session.start
        }
    }
}

/// A timed session laid out like `EventRow`, with the activity's color. Click to edit.
private struct DaySessionRow: View {
    @Environment(AppModel.self) private var model
    let session: FocusSession

    var body: some View {
        let activity = model.activity(session.activityID)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            // The dot sits in the gap before the name, so names line up with the meetings'.
            Text(activity?.name ?? "Atividade removida")
                .overlay(alignment: .leading) {
                    Circle().fill(Color(hex: activity?.colorHex ?? "")).frame(width: 7, height: 7).offset(x: -10)
                }
            Spacer()
            Text(DurationFormat.short(session.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
        .help("Sessão cronometrada · clique para editar")
    }
}

/// "No que você vai trabalhar agora?": type to pick an area (or create one) and the timer starts.
struct StartBox: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Começar agora").font(Theme.font(size: 14, weight: .semibold))
            Text("Escolha uma atividade; só iniciaremos quando você confirmar.")
                .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
            if let running = model.runningActivity {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: running.colorHex)).frame(width: 10, height: 10)
                    Text("Agora: \(running.name)").fontWeight(.medium)
                    Text(DurationFormat.clock(model.currentElapsed)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Pausar") { model.toggle(running.id) }
                }
            }
            ForEach(model.activeActivities) { area in
                Button { model.route = .timer } label: {
                    HStack(spacing: 6) {
                        IconView(icon: area.icon, base: model.imagesFolder, fallback: "circle.fill", size: 14)
                            .foregroundStyle(Color(hex: area.colorHex))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(area.name).foregroundStyle(Theme.text)
                            Text(area.goalID.flatMap(model.goal)?.title ?? "Atividade independente")
                                .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Button("Criar e começar outra atividade   ›") { showingNewActivity = true }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border.opacity(0.5)))
        .floatingSheet(isPresented: $showingNewActivity) { ActivityEditor(activity: nil) }
    }

}

/// An objective's progress in one line.
private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    let thread: GoalThread

    var body: some View {
        let goal = thread.goal
        let progress = model.progress(for: goal)
        Button { model.route = .goal(goal.id) } label: {
            HStack(spacing: 10) {
                IconView(icon: goal.icon, base: model.imagesFolder, fallback: "flag", size: 18)
                Text(goal.title).frame(width: 200, alignment: .leading).lineLimit(1)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).tint(Theme.accent)
                } else {
                    Spacer()
                }
                Text(progressText(progress)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    .frame(width: 150, alignment: .trailing)
                if thread.state == .stalled {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help("Parado")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func progressText(_ progress: GoalProgress) -> String {
        if let target = progress.targetSeconds {
            return "\(DurationFormat.short(progress.loggedSeconds)) de \(DurationFormat.short(target))"
        }
        return DurationFormat.short(progress.loggedSeconds)
    }
}

struct HabitTodayRow: View {
    @Environment(AppModel.self) private var model
    let habit: Habit
    let tracker: HabitTracker
    let now: Date

    var body: some View {
        let done = tracker.isDone(habit, on: now)
        let onlyByTimer = tracker.isDoneByTimer(habit, on: now) && !tracker.isChecked(habit, on: now)
        HStack(spacing: 10) {
            Button {
                model.toggleHabit(habit.id, on: now)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(Color(hex: habit.colorHex))
            }
            .buttonStyle(.plain)
            .disabled(onlyByTimer)
            Text(habit.name)
            Spacer()
            let streak = tracker.currentStreak(habit, now: now)
            if streak > 0 {
                Text(streak == 1 ? "1 dia seguido" : "\(streak) dias seguidos")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

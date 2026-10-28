import OrganizadorCore
import SwiftUI

/// An objective opened as a project: progress, the timer button, where you left off,
/// and its notes, tasks, habits and areas.
struct GoalPage: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    @State private var editing = false
    @State private var addingArea = false
    @State private var newTask = ""

    var body: some View {
        let thread = model.thread(for: goal.id)
        let areas = model.activities(forGoal: goal.id).filter { !$0.isArchived }

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    icon: goal.icon, cover: goal.cover, base: model.imagesFolder, fallback: "flag",
                    imagesFolder: model.imagesFolder,
                    setIcon: { icon in update { $0.icon = icon } },
                    setCover: { cover in update { $0.cover = cover } }
                ) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(goal.title).font(.system(size: 36, weight: .bold))
                        if let thread { StateBadge(state: thread.state) }
                    }
                }

                VStack(alignment: .leading, spacing: 28) {
                    actions(areas)
                    if let thread { numbers(thread) }
                    if let thread { leftOff(thread) }
                    notes
                    tasks
                    habits(areas)
                    areaList(areas)
                }
                .padding(.horizontal, 48)
            }
            .padding(.bottom, 48)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) { GoalEditor(goal: goal) }
        .sheet(isPresented: $addingArea) { ActivityEditor(activity: nil, goalID: goal.id) }
    }

    private func update(_ change: (inout Goal) -> Void) {
        var updated = goal
        change(&updated)
        model.updateGoal(updated)
    }

    private func actions(_ areas: [Activity]) -> some View {
        HStack(spacing: 10) {
            let running = model.running.flatMap { running in areas.first { $0.id == running.activityID } }
            if let running {
                Button("Pausar \(running.name)", systemImage: "pause.fill") { model.toggle(running.id) }
                    .buttonStyle(.borderedProminent)
            } else if areas.count == 1 {
                Button("Trabalhar nisso", systemImage: "play.fill") { model.start(areas[0].id) }
                    .buttonStyle(.borderedProminent)
            } else if areas.isEmpty {
                Button("Criar área para cronometrar", systemImage: "plus") { addingArea = true }
            } else {
                Menu {
                    ForEach(areas) { area in
                        Button(area.name) { model.start(area.id) }
                    }
                } label: {
                    Label("Trabalhar nisso", systemImage: "play.fill")
                }
                .fixedSize()
            }
            Spacer()
            Menu("Estado") {
                Button("Ativo") { model.setGoalStatus(goal.id, .active) }
                Button("Pausar") { model.setGoalStatus(goal.id, .paused) }
                Button("Encerrar") { model.setGoalStatus(goal.id, .closed) }
            }
            .fixedSize()
            Button("Editar") { editing = true }
        }
    }

    private func numbers(_ thread: GoalThread) -> some View {
        let progress = model.progress(for: goal)
        return HStack(alignment: .top, spacing: 32) {
            stat("Progresso") {
                if let target = progress.targetSeconds, let fraction = progress.fraction {
                    Text("\(DurationFormat.short(progress.loggedSeconds)) de \(DurationFormat.short(target))")
                    ProgressView(value: fraction).tint(progress.isComplete ? .green : Theme.accent).frame(width: 160)
                } else {
                    Text(DurationFormat.short(progress.loggedSeconds))
                }
            }
            if let deadline = goal.deadline {
                stat("Prazo") {
                    Text("\(dDay(deadline, now: model.now, calendar: model.calendar)) · \(deadline.formatted(date: .abbreviated, time: .omitted))")
                    if progress.isOverdue {
                        Text("O prazo passou").foregroundStyle(.red)
                    } else if let perWeek = progress.requiredSecondsPerWeek, perWeek > 0 {
                        Text("Ritmo necessário: \(DurationFormat.short(perWeek))/semana").foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            stat("Nesta semana") {
                if let intended = thread.weeklyTargetSeconds {
                    Text("\(DurationFormat.short(thread.weekSeconds)) de \(DurationFormat.short(intended)) pretendidas")
                    ProgressView(value: min(1, thread.weekSeconds / intended)).tint(Theme.accent).frame(width: 160)
                } else {
                    Text(DurationFormat.short(thread.weekSeconds))
                }
            }
        }
    }

    private func stat<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            content()
        }
        .monospacedDigit()
    }

    private func leftOff(_ thread: GoalThread) -> some View {
        PageSection(title: "Onde parei") {
            VStack(alignment: .leading, spacing: 6) {
                if let session = thread.lastSession {
                    Label(
                        "\(model.activity(session.activityID)?.name ?? "Área") · \(session.end.formatted(.relative(presentation: .named))) · \(DurationFormat.short(session.duration))",
                        systemImage: "timer"
                    )
                }
                if let note = thread.lastNote {
                    Button { model.route = .note(note.url) } label: {
                        Label("\(note.title) · editada \(note.modifiedAt.formatted(.relative(presentation: .named)))", systemImage: "note.text")
                    }
                    .buttonStyle(.plain)
                }
                if let task = thread.nextTask {
                    Label("Próximo passo: \(task.title)", systemImage: "arrow.right.circle")
                }
                if thread.lastSession == nil, thread.lastNote == nil, thread.nextTask == nil {
                    Text("Nada registrado ainda. Comece o cronômetro, escreva uma nota ou crie uma tarefa.")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var notes: some View {
        let linked = NoteGraph.backlinks(to: goal.title, in: model.notes.notes).sorted { $0.modifiedAt > $1.modifiedAt }
        return PageSection(title: "Notas") {
            if linked.isEmpty {
                Text("Notas com [[\(goal.title)]] aparecem aqui.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(linked) { note in
                Button { model.route = .note(note.url) } label: {
                    HStack(spacing: 8) {
                        IconView(icon: FrontMatter.parse(note.body).0.icon, base: model.notes.folder, size: 16)
                        Text(note.title)
                        Spacer()
                        Text(note.modifiedAt.formatted(.relative(presentation: .named))).foregroundStyle(Theme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } accessory: {
            Button("Nova nota", systemImage: "plus") {
                if let note = model.notes.create(body: "[[\(goal.title)]]\n\n") { model.route = .note(note.url) }
            }
            .buttonStyle(.borderless)
        }
    }

    private var tasks: some View {
        let linked = model.data.tasks.filter { $0.goalID == goal.id }
        let open = linked.filter { !$0.isDone }
        let done = TaskLists.completed(linked).prefix(3)
        return PageSection(title: "Tarefas") {
            ForEach(open) { TaskRow(task: $0) }
            ForEach(Array(done)) { TaskRow(task: $0) }
            TextField("Nova tarefa (Enter para adicionar)", text: $newTask)
                .textFieldStyle(.plain)
                .onSubmit {
                    let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    model.saveTask(TaskItem(title: title, goalID: goal.id))
                    newTask = ""
                }
        }
    }

    @ViewBuilder
    private func habits(_ areas: [Activity]) -> some View {
        let ids = Set(areas.map(\.id))
        let linked = model.data.habits.filter { $0.autoActivityID.map(ids.contains) ?? false }
        if !linked.isEmpty {
            let tracker = model.habitTracker
            PageSection(title: "Hábitos") {
                ForEach(linked) { HabitTodayRow(habit: $0, tracker: tracker, now: model.now) }
            }
        }
    }

    private func areaList(_ areas: [Activity]) -> some View {
        PageSection(title: "Áreas") {
            if areas.isEmpty {
                Text("Nenhuma área ligada. O tempo das áreas ligadas vira progresso.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(areas) { area in
                Button { model.route = .area(area.id) } label: {
                    HStack(spacing: 8) {
                        IconView(icon: area.icon, base: model.imagesFolder, fallback: "circle.fill", size: 16)
                            .foregroundStyle(Color(hex: area.colorHex))
                        Text(area.name)
                        Spacer()
                        Text("\(DurationFormat.short(model.weekTotal(for: area.id))) nesta semana")
                            .monospacedDigit().foregroundStyle(Theme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } accessory: {
            Button("Nova área", systemImage: "plus") { addingArea = true }
                .buttonStyle(.borderless)
        }
    }
}

private struct StateBadge: View {
    let state: GoalThread.State

    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .active: ("ativo", .green)
        case .stalled: ("parado", .orange)
        case .paused: ("pausado", .gray)
        case .closed: ("encerrado", .gray)
        }
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

struct GoalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let goal: Goal?
    @State private var title: String
    @State private var hasTarget: Bool
    @State private var targetHours: Double
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var startDate: Date
    @State private var hasWeekly: Bool
    @State private var weeklyHours: Double
    @State private var staleDays: Int
    @State private var activityIDs: Set<UUID> = []

    init(goal: Goal?) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _hasTarget = State(initialValue: goal?.targetHours != nil)
        _targetHours = State(initialValue: goal?.targetHours ?? 100)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? Date().addingTimeInterval(90 * 86_400))
        _startDate = State(initialValue: goal?.startDate ?? Date())
        _hasWeekly = State(initialValue: goal?.weeklyHours != nil)
        _weeklyHours = State(initialValue: goal?.weeklyHours ?? 3)
        _staleDays = State(initialValue: goal?.staleDays ?? Goal.defaultStaleDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(goal == nil ? "Novo objetivo" : "Editar objetivo").font(.headline)

            Form {
                TextField("Título", text: $title)

                Toggle("Alvo em horas", isOn: $hasTarget)
                if hasTarget {
                    TextField("Horas", value: $targetHours, format: .number)
                }

                Toggle("Prazo", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Até", selection: $deadline, displayedComponents: .date)
                }

                DatePicker("Contar tempo a partir de", selection: $startDate, displayedComponents: .date)

                Section("Fio da meada") {
                    Toggle("Ritmo semanal pretendido", isOn: $hasWeekly)
                    if hasWeekly {
                        TextField("Horas por semana", value: $weeklyHours, format: .number)
                    }
                    Stepper("Parado após \(staleDays == 1 ? "1 dia" : "\(staleDays) dias") sem mexer", value: $staleDays, in: 1...90)
                }

                Section("Áreas que contam para este objetivo") {
                    if model.activeActivities.isEmpty {
                        Text("Crie áreas no Cronômetro primeiro.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.activeActivities) { activity in
                        Toggle(isOn: isSelected(activity.id)) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: activity.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(activity.name)
                                if let other = otherGoalTitle(for: activity) {
                                    Text("hoje conta para \(other)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 420)

            HStack {
                if let goal {
                    Button("Excluir objetivo", role: .destructive) {
                        model.deleteGoal(goal.id)
                        model.route = .home
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let goal {
                activityIDs = Set(model.activities(forGoal: goal.id).map(\.id))
            }
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && (!hasTarget || targetHours > 0) && (!hasWeekly || weeklyHours > 0)
    }

    private func isSelected(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { activityIDs.contains(id) },
            set: { selected in
                if selected { activityIDs.insert(id) } else { activityIDs.remove(id) }
            }
        )
    }

    /// The goal the activity feeds today, when it is not this one.
    private func otherGoalTitle(for activity: Activity) -> String? {
        guard let goalID = activity.goalID, goalID != goal?.id else { return nil }
        return model.goal(goalID)?.title
    }

    private func save() {
        let calendar = model.calendar
        let endOfDeadlineDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: deadline) ?? deadline
        // Starts from the stored goal so icon, cover and status survive editing.
        var saved = goal ?? Goal(title: trimmedTitle)
        saved.title = trimmedTitle
        saved.targetHours = hasTarget ? targetHours : nil
        saved.startDate = calendar.startOfDay(for: startDate)
        saved.deadline = hasDeadline ? endOfDeadlineDay : nil
        saved.weeklyHours = hasWeekly ? weeklyHours : nil
        saved.staleDays = staleDays
        model.saveGoal(saved, activityIDs: activityIDs)
        if goal == nil { model.route = .goal(saved.id) }
        dismiss()
    }
}

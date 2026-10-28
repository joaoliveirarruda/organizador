import AppKit
import OrganizadorCore
import SwiftUI

/// Home: a greeting, one box to start working, the day, and how every objective is doing.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var newTask = ""
    @State private var creatingTask = false
    @State private var editingTask: TaskItem?
    @State private var deletingTask: TaskItem?

    var body: some View {
        let now = model.now
        let threads = model.threads
        let active = threads.filter { $0.state == .active || $0.state == .stalled }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(section: "Início", title: greeting(now), subtitle: now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized + " · seu dia com clareza")

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

                PageSection(title: "Meu dia") {
                    dayContent(now)
                } accessory: {
                    Button("Ver agenda →") { model.route = .agenda }.buttonStyle(.plain)
                }

                if !active.isEmpty {
                    PageSection(title: "Retomar de onde parei") {
                        ForEach(active, id: \.goal.id) { thread in
                            ThreadRow(thread: thread)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Nova tarefa") { creatingTask = true }
                        .buttonStyle(AppActionButtonStyle(width: 288))
                    Button("Nova nota") { if let note = model.notes.create() { model.route = .note(note.url) } }
                        .buttonStyle(AppActionButtonStyle(width: 288))
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $creatingTask) { TaskEditor(task: nil) }
        .sheet(item: $editingTask) { TaskEditor(task: $0) }
        .confirmationDialog("Excluir tarefa?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible, presenting: deletingTask) { task in
            Button("Excluir tarefa", role: .destructive) { model.deleteTask(task.id); deletingTask = nil }
        } message: { _ in Text("A tarefa será removida.") }
    }

    @ViewBuilder
    private func dayContent(_ now: Date) -> some View {
        let events = model.calendarEvents(on: now)
        let tracker = model.habitTracker
        VStack(alignment: .leading, spacing: 10) {
            if !model.hasCalendar {
                HStack {
                    Text("Conecte o Google Agenda para ver suas reuniões aqui.").foregroundStyle(Theme.secondaryText)
                    SettingsLink { Text("Abrir Ajustes") }
                }
            } else if events.isEmpty {
                Text("Nenhuma reunião hoje.").foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(events) { event in
                    EventRow(event: event, now: now)
                        .contentShape(Rectangle())
                        .onTapGesture { model.route = .agenda }
                }
            }
            Divider()
            ForEach(model.todayTasks) { task in
                TaskRow(task: task)
                    .contentShape(Rectangle())
                    .onTapGesture { editingTask = task }
                    .contextMenu {
                        Button("Editar") { editingTask = task }
                        Button("Excluir", role: .destructive) { deletingTask = task }
                    }
            }
            TextField("Nova tarefa para hoje (Enter para adicionar)", text: $newTask)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
            if !model.data.habits.isEmpty {
                Divider()
                ForEach(model.data.habits) { habit in
                    HabitTodayRow(habit: habit, tracker: tracker, now: now)
                }
            }
        }
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
        model.addTask(title: title, dueToday: true)
        newTask = ""
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
        .sheet(isPresented: $showingNewActivity) { ActivityEditor(activity: nil) }
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

import AppKit
import OrganizadorCore
import SwiftUI

/// Home: a greeting, one box to start working, the day, and how every objective is doing.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var newTask = ""

    var body: some View {
        let now = model.now
        let threads = model.threads
        let stalled = threads.filter { $0.state == .stalled }
        let active = threads.filter { $0.state == .active || $0.state == .stalled }

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting(now)).font(.system(size: 32, weight: .bold))
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                        .foregroundStyle(Theme.secondaryText)
                }

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

                if !stalled.isEmpty {
                    PageSection(title: "Paradas") {
                        ForEach(stalled, id: \.goal.id) { thread in
                            StalledCard(thread: thread)
                        }
                    }
                }

                PageSection(title: "Meu dia") {
                    dayContent(now)
                }

                if !active.isEmpty {
                    PageSection(title: "Frentes") {
                        ForEach(active, id: \.goal.id) { thread in
                            ThreadRow(thread: thread)
                        }
                    }
                }

                WeekPlan(threads: threads.filter { $0.state != .closed })
            }
            .padding(48)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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
                ForEach(events) { EventRow(event: $0, now: now) }
            }
            Divider()
            ForEach(model.todayTasks) { TaskRow(task: $0) }
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
    @State private var query = ""

    var body: some View {
        let matches = self.matches
        VStack(alignment: .leading, spacing: 12) {
            if let running = model.runningActivity {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: running.colorHex)).frame(width: 10, height: 10)
                    Text("Agora: \(running.name)").fontWeight(.medium)
                    Text(DurationFormat.clock(model.currentElapsed)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Pausar") { model.toggle(running.id) }
                }
            }
            TextField("No que você vai trabalhar agora?", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .onSubmit(startFirst)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(matches) { area in
                        Button {
                            model.start(area.id)
                            query = ""
                        } label: {
                            HStack(spacing: 6) {
                                IconView(icon: area.icon, base: model.imagesFolder, fallback: "circle.fill", size: 14)
                                    .foregroundStyle(Color(hex: area.colorHex))
                                Text(area.name)
                                Image(systemName: "play.fill").font(.caption2).foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().stroke(Theme.border))
                        }
                        .buttonStyle(.plain)
                    }
                    if matches.isEmpty, !trimmed.isEmpty {
                        Text("Enter cria a área “\(trimmed)” e começa a contar").foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: [Activity] {
        guard !trimmed.isEmpty else { return model.activeActivities }
        return model.activeActivities.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func startFirst() {
        guard !trimmed.isEmpty else { return }
        let area = matches.first ?? model.addActivity(name: trimmed, colorHex: Palette.colors.randomElement()!)
        model.start(area.id)
        query = ""
    }
}

/// A stalled objective, with the three deliberate ways out.
private struct StalledCard: View {
    @Environment(AppModel.self) private var model
    let thread: GoalThread

    var body: some View {
        let goal = thread.goal
        HStack(spacing: 10) {
            IconView(icon: goal.icon, base: model.imagesFolder, fallback: "flag", size: 20)
            Button("\(goal.title) · parado há \(GoalThreads.days(thread.idleDays))") { model.route = .goal(goal.id) }
                .buttonStyle(.plain)
                .fontWeight(.medium)
            Spacer()
            Button("Retomar") { resume() }
            Button("Pausar") { model.setGoalStatus(goal.id, .paused) }
            Button("Encerrar") { model.setGoalStatus(goal.id, .closed) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    /// Starts the area worked on last (or the goal's first area) and opens the goal.
    private func resume() {
        let goalID = thread.goal.id
        let areas = model.activities(forGoal: goalID).filter { !$0.isArchived }
        let last = thread.lastSession.map(\.activityID).flatMap { id in areas.first { $0.id == id } }
        if let area = last ?? areas.first { model.start(area.id) }
        model.route = .goal(goalID)
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

/// This week: intended versus real, per objective, plus areas without one.
struct WeekPlan: View {
    @Environment(AppModel.self) private var model
    let threads: [GoalThread]

    var body: some View {
        let rows = threads.filter { $0.weeklyTargetSeconds != nil || $0.weekSeconds > 0 }
        let loose = model.looseAreasWeekTotal
        if !rows.isEmpty || loose > 0 {
            PageSection(title: "Esta semana · pretendido × real") {
                ForEach(rows, id: \.goal.id) { thread in
                    row(title: thread.goal.title, real: thread.weekSeconds, intended: thread.weeklyTargetSeconds)
                }
                if loose > 0 {
                    row(title: "Áreas soltas", real: loose, intended: nil)
                }
            }
        }
    }

    private func row(title: String, real: TimeInterval, intended: TimeInterval?) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 200, alignment: .leading).lineLimit(1)
            if let intended, intended > 0 {
                ProgressView(value: min(1, real / intended)).tint(real >= intended ? .green : Theme.accent)
                Text("\(DurationFormat.short(real)) de \(DurationFormat.short(intended))")
                    .monospacedDigit().foregroundStyle(Theme.secondaryText).frame(width: 150, alignment: .trailing)
            } else {
                Spacer()
                Text(DurationFormat.short(real)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
        }
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

import OrganizadorCore
import SwiftUI

/// Home screen: today's meetings, timed work, tasks and habits in one place.
struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var newTask = ""

    var body: some View {
        let now = model.now
        let events = model.calendarEvents(on: now)
        let tracker = model.habitTracker

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(.largeTitle.weight(.semibold))

                TodaySummary()

                DayTimeline(segments: model.todayTimeline, meetings: meetingFractions(events)) { id in
                    Color(hex: model.activity(id)?.colorHex ?? "")
                }

                TodaySection(title: "Agenda", systemImage: "calendar") {
                    if !model.hasCalendar {
                        HStack {
                            Text("Conecte o Google Agenda para ver suas reuniões aqui.")
                                .foregroundStyle(.secondary)
                            SettingsLink { Text("Abrir Ajustes") }
                        }
                    } else if events.isEmpty {
                        Text("Nenhuma reunião hoje.").foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            EventRow(event: event, now: now)
                        }
                    }
                }

                TodaySection(title: "Tarefas", systemImage: "checklist") {
                    ForEach(model.todayTasks) { task in
                        TaskRow(task: task)
                    }
                    TextField("Nova tarefa para hoje (Enter para adicionar)", text: $newTask)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTask)
                }

                if !model.data.habits.isEmpty {
                    TodaySection(title: "Hábitos", systemImage: "repeat") {
                        ForEach(model.data.habits) { habit in
                            HabitTodayRow(habit: habit, tracker: tracker, now: now)
                        }
                    }
                }

                TodaySection(title: "Cronômetro", systemImage: "timer") {
                    ForEach(model.activeActivities) { activity in
                        ActivityToggleRow(activity: activity, compact: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Hoje")
    }

    /// Timed meetings as fractions of today, for the timeline.
    private func meetingFractions(_ events: [CalendarEvent]) -> [ClosedRange<Double>] {
        let day = model.today
        return events.compactMap { event -> ClosedRange<Double>? in
            guard !event.isAllDay else { return nil }
            let start = max(event.start, day.start).timeIntervalSince(day.start) / day.duration
            let end = min(event.end, day.end).timeIntervalSince(day.start) / day.duration
            return start < end ? start...end : nil
        }
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        model.addTask(title: title, dueToday: true)
        newTask = ""
    }
}

private struct TodaySection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
    }
}

private struct HabitTodayRow: View {
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

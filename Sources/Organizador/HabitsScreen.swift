import OrganizadorCore
import SwiftUI

struct HabitsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editingHabit: Habit?
    @State private var addingHabit = false

    var body: some View {
        let tracker = model.habitTracker
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(section: "Hoje", title: "Hábitos", subtitle: "Marque o dia ou deixe o tempo fazer a contagem.") {
                    Button("Novo hábito") { addingHabit = true }
                        .buttonStyle(.heading(primary: true))
                        .keyboardShortcut("n")
                }
                if model.data.habits.isEmpty {
                    PageSection(title: "Nenhum hábito ainda") {
                        Text("Crie um hábito e marque os dias em que fez. Ele também pode ser marcado sozinho pelo cronômetro.")
                            .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                        Button("Criar primeiro hábito") { addingHabit = true }.buttonStyle(.heading(primary: true))
                    }
                } else {
                    ForEach(model.data.habits) { habit in
                        HabitCard(habit: habit, tracker: tracker) { editingHabit = habit }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $addingHabit) {
            HabitEditor(habit: nil)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditor(habit: habit)
        }
    }
}

struct HabitCard: View {
    @Environment(AppModel.self) private var model
    let habit: Habit
    let tracker: HabitTracker
    let onEdit: () -> Void
    @State private var showingConsistency = false

    var body: some View {
        let now = model.now
        let doneToday = tracker.isDone(habit, on: now)
        let onlyByTimer = tracker.isDoneByTimer(habit, on: now) && !tracker.isChecked(habit, on: now)
        let streak = tracker.currentStreak(habit, now: now)
        let rate = tracker.completionRate(habit, days: 30, now: now)
        let color = Color(hex: habit.colorHex)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.title3.weight(.semibold))
                    Text("\(streak) \(streak == 1 ? "dia" : "dias") seguidos · \(Int((rate * 30).rounded())) de 30 dias")
                        .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(streak)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(streak == 1 ? "dia seguido" : "dias seguidos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Editar hábito")
            }

            Text(subtitle).font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 16) {
                Button(doneToday ? "Desmarcar hoje" : "Marcar hoje") { model.toggleHabit(habit.id, on: now) }
                    .buttonStyle(.plain)
                    .disabled(onlyByTimer)
                Button("Ver constância   ›") { showingConsistency = true }.buttonStyle(.plain)
                if onlyByTimer, let activityID = habit.autoActivityID {
                    Button("Ver origem da marcação   ›") { model.route = .area(activityID) }.buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .contextMenu {
            Button("Editar", action: onEdit)
        }
        .sheet(isPresented: $showingConsistency) {
            VStack(alignment: .leading, spacing: 16) {
                Text(habit.name).font(.title2.weight(.semibold))
                Text("Constância · últimas 12 semanas").foregroundStyle(Theme.secondaryText)
                HabitGrid(habit: habit, tracker: tracker, color: color, now: now)
                Button("Fechar") { showingConsistency = false }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 520)
        }
    }

    private var subtitle: String {
        if let activityID = habit.autoActivityID, let activity = model.activity(activityID) {
            return "Automático: \(habit.autoMinutes) min de \(activity.name) no cronômetro"
        }
        return "Marcado à mão"
    }
}

/// The last 12 weeks, one column per week. Click a past day to check or uncheck it.
struct HabitGrid: View {
    @Environment(AppModel.self) private var model
    let habit: Habit
    let tracker: HabitTracker
    let color: Color
    let now: Date

    private static let weeks = 12

    var body: some View {
        let calendar = tracker.calendar
        let today = calendar.startOfDay(for: now)
        let anchor = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: today) ?? today
        let firstDay = Stats.week(containing: anchor, calendar: calendar).start

        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<Self.weeks, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstDay) ?? firstDay
                        cell(day: day, today: today, calendar: calendar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(day: Date, today: Date, calendar: Calendar) -> some View {
        let isFuture = day > today
        let done = !isFuture && tracker.isDone(habit, on: day)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        RoundedRectangle(cornerRadius: 3)
            .fill(isFuture ? Color.clear : (done ? color : Color.secondary.opacity(0.15)))
            .frame(width: 14, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(isToday ? 0.6 : 0), lineWidth: 1)
            )
            .help(day.formatted(date: .abbreviated, time: .omitted))
            .onTapGesture {
                if !isFuture { model.toggleHabit(habit.id, on: day) }
            }
    }
}

struct HabitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habit: Habit?
    @State private var name: String
    @State private var colorHex: String
    @State private var isAutomatic: Bool
    @State private var autoActivityID: UUID?
    @State private var autoMinutes: Int
    @State private var confirmingDelete = false

    init(habit: Habit?) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _colorHex = State(initialValue: habit?.colorHex ?? Palette.colors[2])
        _isAutomatic = State(initialValue: habit?.autoActivityID != nil)
        _autoActivityID = State(initialValue: habit?.autoActivityID)
        _autoMinutes = State(initialValue: habit?.autoMinutes ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(habit == nil ? "Novo hábito" : "Editar hábito").font(.headline)
            Form {
                TextField("Nome", text: $name)
                HStack(spacing: 8) {
                    ForEach(Palette.colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary, lineWidth: hex == colorHex ? 2 : 0))
                            .onTapGesture { colorHex = hex }
                    }
                }
                Toggle("Marcar sozinho pelo cronômetro", isOn: $isAutomatic)
                if isAutomatic {
                    Picker("Atividade", selection: $autoActivityID) {
                        Text("Escolha…").tag(UUID?.none)
                        ForEach(model.activeActivities) { activity in
                            Text(activity.name).tag(Optional(activity.id))
                        }
                    }
                    Stepper("Pelo menos \(autoMinutes) min no dia", value: $autoMinutes, in: 5...480, step: 5)
                }
            }
            HStack {
                if habit != nil {
                    Button("Excluir", role: .destructive) {
                        confirmingDelete = true
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
        .frame(width: 440)
        .confirmationDialog("Excluir hábito?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if let habit {
                Button("Excluir hábito", role: .destructive) {
                    model.deleteHabit(habit.id)
                    dismiss()
                }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && (!isAutomatic || autoActivityID != nil)
    }

    private func save() {
        var saved = habit ?? Habit(name: trimmedName, colorHex: colorHex)
        saved.name = trimmedName
        saved.colorHex = colorHex
        saved.autoActivityID = isAutomatic ? autoActivityID : nil
        saved.autoMinutes = autoMinutes
        model.saveHabit(saved)
        dismiss()
    }
}

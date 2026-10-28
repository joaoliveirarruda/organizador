import OrganizadorCore
import SwiftUI

/// Goals fed by the time logged on their activities.
struct GoalsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editingGoal: Goal?
    @State private var addingGoal = false

    var body: some View {
        Group {
            if model.data.goals.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma meta ainda", systemImage: "flag")
                } description: {
                    Text("Crie uma meta e escolha as atividades que contam para ela. O tempo cronometrado nessas atividades vira progresso.")
                } actions: {
                    Button("Nova meta") { addingGoal = true }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.sortedGoals) { goal in
                            GoalCard(goal: goal)
                                .contentShape(Rectangle())
                                .onTapGesture { editingGoal = goal }
                                .contextMenu {
                                    Button("Editar") { editingGoal = goal }
                                    Button("Excluir", role: .destructive) { model.deleteGoal(goal.id) }
                                }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 720)
                }
            }
        }
        .navigationTitle("Metas")
        .toolbar {
            ToolbarItem {
                Button {
                    addingGoal = true
                } label: {
                    Label("Nova meta", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $addingGoal) {
            GoalEditor(goal: nil)
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditor(goal: goal)
        }
    }
}

struct GoalCard: View {
    @Environment(AppModel.self) private var model
    let goal: Goal

    var body: some View {
        let progress = model.progress(for: goal)
        let activities = model.activities(forGoal: goal.id)
        let status = statusLine(progress)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title).font(.title3.weight(.semibold))
                Spacer()
                if let deadline = goal.deadline {
                    Text("até \(deadline.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
            }

            if let fraction = progress.fraction, let target = progress.targetSeconds {
                ProgressView(value: fraction)
                    .tint(progress.isComplete ? Color.green : Color.accentColor)
                Text("\(DurationFormat.short(progress.loggedSeconds)) de \(DurationFormat.short(target)) · \(Int((fraction * 100).rounded(.down)))%")
                    .monospacedDigit()
            } else {
                Text("\(DurationFormat.short(progress.loggedSeconds)) registradas")
                    .monospacedDigit()
            }

            Text(status.text)
                .font(.callout)
                .foregroundStyle(status.color)

            if activities.isEmpty {
                Text("Nenhuma atividade ligada. Clique para escolher.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(activities) { activity in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: activity.colorHex))
                                .frame(width: 8, height: 8)
                            Text(activity.name).font(.callout)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private func statusLine(_ progress: GoalProgress) -> (text: String, color: Color) {
        let week = model.thisWeekTotal(for: goal)
        if progress.isComplete {
            return ("Meta concluída", .green)
        }
        if progress.isOverdue {
            return ("O prazo passou", .red)
        }
        if let perWeek = progress.requiredSecondsPerWeek {
            let onTrack = week >= perWeek
            return (
                "Ritmo necessário: \(DurationFormat.short(perWeek)) por semana · esta semana \(DurationFormat.short(week))",
                onTrack ? .green : .secondary
            )
        }
        return ("Esta semana: \(DurationFormat.short(week))", .secondary)
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
    @State private var activityIDs: Set<UUID> = []

    init(goal: Goal?) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _hasTarget = State(initialValue: goal == nil || goal?.targetHours != nil)
        _targetHours = State(initialValue: goal?.targetHours ?? 100)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? Date().addingTimeInterval(90 * 86_400))
        _startDate = State(initialValue: goal?.startDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(goal == nil ? "Nova meta" : "Editar meta").font(.headline)

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

                Section("Atividades que contam para esta meta") {
                    if model.activeActivities.isEmpty {
                        Text("Crie atividades no Cronômetro primeiro.")
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
                    Button("Excluir meta", role: .destructive) {
                        model.deleteGoal(goal.id)
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
        !trimmedTitle.isEmpty && (!hasTarget || targetHours > 0)
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
        let saved = Goal(
            id: goal?.id ?? UUID(),
            title: trimmedTitle,
            targetHours: hasTarget ? targetHours : nil,
            startDate: calendar.startOfDay(for: startDate),
            deadline: hasDeadline ? endOfDeadlineDay : nil
        )
        model.saveGoal(saved, activityIDs: activityIDs)
        dismiss()
    }
}

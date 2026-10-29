import OrganizadorCore
import ShadcnUI
import SwiftUI

enum TaskFilter: String, CaseIterable, Identifiable {
    case today, upcoming, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Hoje"
        case .upcoming: "Próximas"
        case .completed: "Concluídas"
        }
    }
}

struct TasksScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter: TaskFilter = .today
    @State private var newTitle = ""
    @State private var editingTask: TaskItem?
    @State private var creatingTask = false
    @State private var deletingTask: TaskItem?

    var body: some View {
        let visible = tasks(for: filter)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(section: "Tarefas", title: filter.title, subtitle: listSubtitle(filter)) {
                    SegmentedTabs(options: TaskFilter.allCases.map { ($0, $0.title) }, selection: $filter)
                    Button("Nova tarefa") { creatingTask = true }
                        .buttonStyle(.heading(primary: true))
                        .keyboardShortcut("n")
                }
                PageSection(title: "") {
                    if filter != .completed {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").foregroundStyle(Theme.secondaryText).frame(width: 22)
                            TextField("Adicionar tarefa (Enter)", text: $newTitle)
                                .textFieldStyle(AppFieldStyle())
                                .onSubmit(addTask)
                        }
                        .padding(.vertical, 6)
                        if !visible.isEmpty { ShadcnSeparator() }
                    }
                    if visible.isEmpty {
                        Text(emptyTitle + " · " + emptyDescription).font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(visible) { task in
                            TaskRow(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = task }
                                .appContextMenu {
                                    Button("Editar") { editingTask = task }
                                    Button("Excluir", role: .destructive) { deletingTask = task }
                                }
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
        .floatingSheet(item: $editingTask) { task in
            TaskEditor(task: task)
        }
        .floatingSheet(isPresented: $creatingTask) { TaskEditor(task: nil) }
        .appConfirm("Excluir tarefa?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible, presenting: deletingTask) { task in
            Button("Excluir tarefa", role: .destructive) { model.deleteTask(task.id); deletingTask = nil }
        } message: { _ in Text("A tarefa será removida.") }
    }

    private func listSubtitle(_ list: TaskFilter) -> String {
        switch list {
        case .today: "Inclui atrasadas"
        case .upcoming: "Futuras e sem prazo"
        case .completed: "Mais recentes primeiro"
        }
    }

    private func tasks(for filter: TaskFilter) -> [TaskItem] {
        switch filter {
        case .today: model.todayTasks
        case .upcoming: model.upcomingTasks
        case .completed: model.completedTasks
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .today: "Nada para hoje"
        case .upcoming: "Nenhuma tarefa futura"
        case .completed: "Nenhuma tarefa concluída"
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .today: "Tarefas com prazo para hoje ou atrasadas aparecem aqui."
        case .upcoming: "Tarefas com prazo depois de hoje ou sem prazo aparecem aqui."
        case .completed: "Marque uma tarefa como feita e ela vem para cá."
        }
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        model.addTask(title: title, due: filter == .today ? Date() : nil)
        newTitle = ""
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            ShadcnCheckbox(isChecked: Binding(get: { task.isDone }, set: { _ in model.toggleTaskDone(task.id) }))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let goalID = task.goalID, let goal = model.goal(goalID) {
                Label(goal.title, systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .help("Prioridade alta")
            }
            if let due = task.dueDate {
                let overdue = model.isOverdue(task)
                // Said in words too, not by the red alone.
                Text((overdue ? "atrasada · " : "") + due.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.callout)
                    .foregroundStyle(overdue ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var dismiss
    let task: TaskItem?
    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TaskPriority
    @State private var goalID: UUID?
    @State private var confirmingDelete = false

    init(task: TaskItem?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _priority = State(initialValue: task?.priority ?? .normal)
        _goalID = State(initialValue: task?.goalID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task == nil ? "Nova tarefa" : "Editar tarefa").font(Theme.font(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                TextField("Título", text: $title)
                TextField("Notas", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("Prazo", isOn: $hasDueDate)
                if hasDueDate {
                    DateField("Dia", selection: $dueDate, displayedComponents: .date)
                }
                ChoicePicker("Prioridade", selection: $priority, choices: [
                    Choice(value: .low, title: "Baixa"), Choice(value: .normal, title: "Normal"), Choice(value: .high, title: "Alta"),
                ])
                ChoicePicker("Objetivo", selection: $goalID, choices: [Choice(value: nil, title: "Nenhum")] + model.sortedGoals.map {
                    Choice(value: Optional($0.id), title: $0.title)
                })
            }
            HStack {
                if task != nil {
                    Button("Excluir", role: .destructive) {
                        confirmingDelete = true
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.heading(primary: true))
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .appConfirm("Excluir tarefa?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if let task {
                Button("Excluir tarefa", role: .destructive) {
                    model.deleteTask(task.id)
                    dismiss()
                }
            }
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        var updated = task ?? TaskItem(title: trimmedTitle)
        updated.title = trimmedTitle
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dueDate = hasDueDate ? model.calendar.startOfDay(for: dueDate) : nil
        updated.priority = priority
        updated.goalID = goalID
        model.saveTask(updated)
        dismiss()
    }
}

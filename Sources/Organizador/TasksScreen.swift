import OrganizadorCore
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
                ScreenHeading(section: "Tarefas", title: filter.title)
                PageSection(title: "Listas") {
                    ForEach(TaskFilter.allCases) { list in
                        Button { filter = list } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(list.title).foregroundStyle(Theme.text)
                                    Text("›").foregroundStyle(Theme.secondaryText)
                                }
                                Text(listSubtitle(list)).font(Theme.font(size: 11)).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                PageSection(title: "Tarefas") {
                    if visible.isEmpty {
                        Text(emptyTitle + " · " + emptyDescription).font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(visible) { task in
                            TaskRow(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = task }
                                .contextMenu {
                                    Button("Editar") { editingTask = task }
                                    Button("Excluir", role: .destructive) { deletingTask = task }
                                }
                                .padding(.vertical, 6)
                        }
                    }
                }
                if filter != .completed {
                    PageSection(title: "Adicionar rapidamente") {
                        TextField("Digite e pressione Enter", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTask)
                    }
                }
                HStack(spacing: 8) {
                    Button("Nova tarefa com detalhes") { creatingTask = true }
                        .buttonStyle(AppActionButtonStyle(primary: true))
                    Menu("Menu da tarefa") {
                        ForEach(visible) { task in
                            Button(task.title) { editingTask = task }
                        }
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .disabled(visible.isEmpty)
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task)
        }
        .sheet(isPresented: $creatingTask) { TaskEditor(task: nil) }
        .confirmationDialog("Excluir tarefa?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible, presenting: deletingTask) { task in
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
            Button {
                model.toggleTaskDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

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
                Text(due.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.callout)
                    .foregroundStyle(model.isOverdue(task) ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
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
            Text(task == nil ? "Nova tarefa" : "Editar tarefa").font(.headline)
            Form {
                TextField("Título", text: $title)
                TextField("Notas", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("Prazo", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Dia", selection: $dueDate, displayedComponents: .date)
                }
                Picker("Prioridade", selection: $priority) {
                    Text("Baixa").tag(TaskPriority.low)
                    Text("Normal").tag(TaskPriority.normal)
                    Text("Alta").tag(TaskPriority.high)
                }
                Picker("Objetivo", selection: $goalID) {
                    Text("Nenhuma").tag(UUID?.none)
                    ForEach(model.sortedGoals) { goal in
                        Text(goal.title).tag(Optional(goal.id))
                    }
                }
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
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .confirmationDialog("Excluir tarefa?", isPresented: $confirmingDelete, titleVisibility: .visible) {
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

import OrganizadorCore
import SwiftUI

/// Every finished session by day, with manual add and edit for when you forgot to start the timer.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editingSession: FocusSession?
    @State private var addingSession = false

    var body: some View {
        let groups = model.sessionsByDay
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nenhuma sessão ainda",
                    systemImage: "timer",
                    description: Text("As sessões aparecem aqui quando você pausa o cronômetro.")
                )
            } else {
                List {
                    ForEach(groups, id: \.day) { group in
                        Section {
                            ForEach(group.sessions) { session in
                                SessionRow(session: session)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingSession = session }
                            }
                        } header: {
                            HStack {
                                Text(group.day.formatted(date: .complete, time: .omitted))
                                Spacer()
                                Text(DurationFormat.short(group.sessions.reduce(0) { $0 + $1.duration }))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Histórico")
        .toolbar {
            ToolbarItem {
                Button {
                    addingSession = true
                } label: {
                    Label("Adicionar sessão", systemImage: "plus")
                }
                .disabled(model.activeActivities.isEmpty)
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditor(session: session)
        }
        .sheet(isPresented: $addingSession) {
            SessionEditor(session: nil)
        }
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: FocusSession

    var body: some View {
        let activity = model.activity(session.activityID)
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: activity?.colorHex ?? ""))
                .frame(width: 10, height: 10)
            Text(activity?.name ?? "Atividade removida")
            Spacer()
            Text("\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
            Text(DurationFormat.clock(session.duration))
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
    }
}

struct SessionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: FocusSession?
    @State private var activityID: UUID?
    @State private var start: Date
    @State private var end: Date

    init(session: FocusSession?) {
        self.session = session
        let now = Date()
        _activityID = State(initialValue: session?.activityID)
        _start = State(initialValue: session?.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: session?.end ?? now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session == nil ? "Adicionar sessão" : "Editar sessão").font(.headline)
            Form {
                Picker("Atividade", selection: $activityID) {
                    ForEach(choices) { activity in
                        Text(activity.name).tag(Optional(activity.id))
                    }
                }
                DatePicker("Início", selection: $start)
                DatePicker("Fim", selection: $end)
                Text("Duração: \(DurationFormat.clock(max(0, end.timeIntervalSince(start))))")
                    .foregroundStyle(end > start ? Color.secondary : Color.red)
            }
            HStack {
                if let session {
                    Button("Excluir", role: .destructive) {
                        model.deleteSession(session.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(activityID == nil || end <= start)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if activityID == nil { activityID = choices.first?.id }
        }
    }

    /// Active activities, plus this session's activity even if it was archived.
    private var choices: [Activity] {
        var list = model.activeActivities
        if let id = session?.activityID, !list.contains(where: { $0.id == id }), let archived = model.activity(id) {
            list.append(archived)
        }
        return list
    }

    private func save() {
        guard let activityID else { return }
        model.saveSession(FocusSession(id: session?.id ?? UUID(), activityID: activityID, start: start, end: end))
        dismiss()
    }
}

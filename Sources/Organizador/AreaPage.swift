import OrganizadorCore
import SwiftUI

/// An area's own page: cover, today's sessions and the week, with manual add and edit
/// for when you forgot to start the timer.
struct AreaPage: View {
    @Environment(AppModel.self) private var model
    let area: Activity
    @State private var editing = false
    @State private var editingSession: FocusSession?
    @State private var addingSession = false

    var body: some View {
        let isRunning = model.running?.activityID == area.id
        let goal = area.goalID.flatMap(model.goal)
        let recent = model.data.sessions
            .filter { $0.activityID == area.id && $0.end > model.now.addingTimeInterval(-7 * 86_400) }
            .sorted { $0.start > $1.start }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: area.icon, cover: area.cover, base: model.imagesFolder, fallback: "circle.fill",
                    imagesFolder: model.imagesFolder,
                    setIcon: { icon in update { $0.icon = icon } },
                    setCover: { cover in update { $0.cover = cover } }
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ÁREA").font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Text(area.name).font(Theme.font(size: 28, weight: .bold))
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button(isRunning ? "Pausar" : "Começar", systemImage: isRunning ? "pause.fill" : "play.fill") {
                            model.toggle(area.id)
                        }
                        .buttonStyle(AppActionButtonStyle(primary: true))
                        .tint(Color(hex: area.colorHex))
                        if let goal {
                            Button { model.route = .goal(goal.id) } label: {
                                Label(goal.title, systemImage: "flag")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text("Atividade solta").foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("Editar") { editing = true }
                    }

                    PageSection(title: "Resumo") {
                        HStack(spacing: 32) {
                            stat("Hoje", model.todayTotal(for: area.id))
                            stat("Nesta semana", model.weekTotal(for: area.id))
                        }
                    }

                    PageSection(title: "Sessões dos últimos 7 dias") {
                        if recent.isEmpty {
                            Text("Nenhuma sessão ainda.").foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(recent) { session in
                            SessionRow(session: session)
                                .contentShape(Rectangle())
                                .onTapGesture { editingSession = session }
                        }
                    } accessory: {
                        Button("Incluir sessão", systemImage: "plus") { addingSession = true }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) { ActivityEditor(activity: area) }
        .sheet(item: $editingSession) { SessionEditor(session: $0) }
        .sheet(isPresented: $addingSession) { SessionEditor(session: nil, activityID: area.id) }
    }

    private func update(_ change: (inout Activity) -> Void) {
        var updated = area
        change(&updated)
        model.updateActivity(updated)
    }

    private func stat(_ title: String, _ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(DurationFormat.short(seconds)).font(.title2.weight(.semibold)).monospacedDigit()
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
            Text("\(session.start.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))–\(session.end.formatted(date: .omitted, time: .shortened))")
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

    init(session: FocusSession?, activityID: UUID? = nil) {
        self.session = session
        let now = Date()
        _activityID = State(initialValue: session?.activityID ?? activityID)
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
